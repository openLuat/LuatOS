const setText = (id, text) => { const element = document.getElementById(id); if (element) element.textContent = text; };
document.getElementById('start')?.addEventListener('click', () => { document.getElementById('pump_status').removeAttribute('data-state'); document.querySelector('#pump_status .status-text').textContent = 'RUNNING'; setText('feedback', 'Pump started'); setText('flow', '12.4 m3/h'); setText('pump_speed', '1,450 rpm'); });
document.getElementById('stop')?.addEventListener('click', () => { document.getElementById('pump_status').dataset.state = 'checked'; document.querySelector('#pump_status .status-text').textContent = 'STOPPED'; setText('feedback', 'Pump stopped'); setText('flow', '0.0 m3/h'); setText('pump_speed', '0 rpm'); });
document.getElementById('details_nav')?.addEventListener('click', () => { window.location.href = 'details.html'; });
document.getElementById('back')?.addEventListener('click', () => { window.location.href = 'index.html'; });
document.getElementById('setpoint')?.addEventListener('change', (event) => { setText('feedback', 'Target updated: ' + event.target.value + ' %'); });
window.PLCUI_READY = true;
