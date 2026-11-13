const N=120;
const round=v=>Math.round(v*100)/100;
const curve=(fn)=>Array.from({length:N},(_,i)=>round(fn(i)));
const primaryTemp=i=>i<15?23-i*.085:i<34?27-(i-15)*.18:i<44?20-(i-34)*.035:i<77?19.5-(i-44)*.018:i<108?18.5-(i-77)*.006:55-7*Math.exp(-(i-108)*.6);
const temperature=[
 {id:'target',color:'#ff4089',values:curve(i=>i<8?18:i<17?30:i===19?0:i===20?60:i===22?50:i<25?20:i<30?25:i<66?30:i<83?16.8:i<90?21.7:17.9)},
 {id:'primary',color:'#ffe23d',values:curve(primaryTemp)},
 {id:'secondary',color:'#78ff8c',values:curve(i=>i>=94&&i<=100?0:primaryTemp(i)+.45+.12*Math.sin(i*.4))},
 {id:'return_primary',color:'#00baff',hidden:true,values:curve(i=>primaryTemp(i)-3.8)},
 {id:'return_secondary',color:'#d7aaff',hidden:true,values:curve(i=>primaryTemp(i)-7.2)},
 {id:'mean',color:'#ffffff',hidden:true,values:curve(()=>22)},
 {id:'outdoor',color:'#ffb871',hidden:true,values:curve(i=>5+2*Math.sin(i*.025))}
];
const pressure=[
 {id:'primary',color:'#ff567c',values:curve(i=>i>=15&&i<21?.33:(i<60?.46:.55)+.014*Math.sin(i*.64)+.009*Math.sin(i*1.43))},
 {id:'primary2',color:'#ffad57',hidden:true,values:curve(i=>.50+.02*Math.sin(i*.5))},
 {id:'return_primary',color:'#00baff',values:curve(i=>i>=100&&i<107?0:(i<60?.6:.56)+.012*Math.sin(i*.74)+.008*Math.sin(i*1.41))},
 {id:'secondary',color:'#78ff8c',values:curve(i=>i>=78&&i<82||i>=100&&i<107?0:i>=15&&i<21?.34:i<31?.59:i<60?.56:.54+.014*Math.sin(i*.8))},
 {id:'return_secondary',color:'#b99aff',hidden:true,values:curve(i=>.51+.015*Math.sin(i*.4))},
 {id:'return_secondary2',color:'#61d6f1',hidden:true,values:curve(i=>.50+.012*Math.sin(i*.45))},
 {id:'difference',color:'#ffe23d',values:curve(i=>.35+i*.00009)}
];
window.STATION_DATA={temperature,pressure,heat:[{id:'heat',color:'#3cddff',values:Array(7).fill(0)}]};
const pageId=document.querySelector('[data-plcui-page]').dataset.plcuiPage;
const menu=document.getElementById('navigation');
document.getElementById('menu_button').onclick=()=>menu.classList.toggle('open');
for(const [key,file] of Object.entries({main:'index.html',parameters:'parameters.html',records:'records.html',trends:'trends.html',pressure:'pressure.html'}))document.getElementById('nav_'+key).onclick=()=>location.href=file;
function drawChart(node){
 const series=window.STATION_DATA[node.dataset.kind];node.dataset.series=JSON.stringify(series);
 const w=parseFloat(node.style.width),h=parseFloat(node.style.height),min=Number(node.dataset.yMin),max=Number(node.dataset.yMax),div=Number(node.dataset.hdiv),bar=node.dataset.chartType==='bar';
 let svg=`<svg viewBox="0 0 ${w} ${h}" xmlns="http://www.w3.org/2000/svg">`;
 for(let i=0;i<div;i++){const y=i*(h-1)/(div-1);svg+=`<line x1="0" x2="${w}" y1="${y}" y2="${y}"/>`;}
 for(const s of series){if(s.hidden)continue;if(bar){s.values.forEach((v,i)=>{if(v>0){const bh=(v-min)*(h-1)/(max-min);svg+=`<rect x="${i*w/s.values.length+4}" y="${h-bh}" width="${w/s.values.length-8}" height="${bh}" fill="${s.color}"/>`;}});}else{const points=s.values.map((v,i)=>`${i*(w-1)/(s.values.length-1)},${(max-v)*(h-1)/(max-min)}`).join(' ');svg+=`<polyline points="${points}" fill="none" stroke="${s.color}" stroke-width="1"/>`;}}
 node.innerHTML=svg+'</svg>';
}
for(const node of document.querySelectorAll('[data-plcui=chart]'))drawChart(node);
for(const node of document.querySelectorAll('[data-series-id]'))node.onclick=()=>{
 const series=window.STATION_DATA[pageId==='pressure'?'pressure':'temperature'];const item=series.find(s=>s.id===node.dataset.seriesId);item.hidden=!item.hidden;
 const check=document.getElementById('curve_'+item.id);check.dataset.state=item.hidden?'normal':'checked';
 const legend=document.getElementById('legend_'+item.id);legend.style.visibility=item.hidden?'hidden':'visible';
 drawChart(document.getElementById('history_chart'));
};
let running=false;
const pump=document.getElementById('pump_control');if(pump)pump.onclick=()=>{running=!running;pump.dataset.state=running?'checked':'normal';document.getElementById('pump_current').textContent=running?'3.8 A':'0.0 A';document.getElementById('pump_frequency').textContent=running?'42.0 Hz':'0.0 Hz';};
const tracking=document.getElementById('tracking_switch');if(tracking)tracking.onclick=()=>{tracking.dataset.state=tracking.dataset.state==='checked'?'normal':'checked';};
const setpoint=document.getElementById('setpoint');if(setpoint)setpoint.onchange=()=>{const value=Number(setpoint.value);if(value>=0&&value<=70)document.getElementById('setpoint_feedback').textContent='输出结果:'+value.toFixed(1)+'℃';};
const columnNames={flow_primary:'一网瞬时流量',heat_primary:'一网瞬时热量',volume_primary:'一网累积流量',total_primary:'一网累积热量',flow_secondary:'二网瞬时流量',heat_secondary:'二网瞬时热量',volume_secondary:'二网累积流量',total_secondary:'二网累积热量',distribution_frequency:'分布泵频率',distribution_current:'分布泵电流',pump_frequency:'循环泵频率',pump_current:'循环泵电流',makeup_frequency:'补水泵频率',makeup_current:'补水泵电流',energy_daily:'一天能耗'};
function refreshTable(query=false){
 const table=document.getElementById('energy_table');if(!table)return;const selected=[...document.querySelectorAll('[id^=column_]')].filter(n=>n.dataset.state==='checked').slice(0,4);
 const heads=table.querySelectorAll('thead th');for(let c=0;c<4;c++){heads[c+1].textContent=selected[c]?columnNames[selected[c].id.slice(7)]:'';for(const row of table.querySelectorAll('tbody tr'))row.children[c+1].textContent=selected[c]?(query?(13.65+c*.21).toFixed(2):'0'):'';}
}
for(const node of document.querySelectorAll('[id^=column_]'))node.onclick=()=>{if(node.dataset.state==='checked')node.dataset.state='normal';else{const selected=[...document.querySelectorAll('[id^=column_]')].filter(n=>n.dataset.state==='checked');if(selected.length>=4)selected[0].dataset.state='normal';node.dataset.state='checked';}refreshTable();};
document.getElementById('query_button')?.addEventListener('click',()=>{refreshTable(true);document.getElementById('result_count').textContent='共 267 条';});
for(const input of document.querySelectorAll('.param-input'))input.addEventListener('change',()=>{if(input.id.startsWith('upper_')||input.id.startsWith('lower_')){const i=Number(input.id.split('_')[1]),up=Number(document.getElementById('upper_'+i).value),lo=Number(document.getElementById('lower_'+i).value),value=parseFloat(document.getElementById('parameter_value_'+i).textContent);const alarm=document.getElementById('alarm_'+i);alarm.textContent=up<=lo?'参数设置错误':value>up?'超上限报警':value<lo?'超下限报警':'正常';alarm.style.visibility=['正常','参数设置错误'].includes(alarm.textContent)?'hidden':'visible';document.getElementById('alarm_normal_'+i).style.visibility=alarm.textContent==='正常'?'visible':'hidden';document.getElementById('alarm_error_'+i).style.visibility=alarm.textContent==='参数设置错误'?'visible':'hidden';}});
window.PLCUI_READY=true;
