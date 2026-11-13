# 白底产品图抠图：从四边 flood fill 去掉连通的近白背景，边缘按亮度羽化，最后裁到内容包围盒。
# 用法： powershell -File tools\cut_bg.ps1 -Src a.png -Dst b.png
param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
)

$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class BgCut
{
    static byte[] buf; static int w, h, stride; static bool[] bg;

    public static string Run(string src, string dst)
    {
        using (Bitmap bmp = new Bitmap(src))
        {
            w = bmp.Width; h = bmp.Height;
            BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            stride = data.Stride;
            int len = stride * h;
            buf = new byte[len];
            Marshal.Copy(data.Scan0, buf, 0, len);
            bg = new bool[w * h];

            Queue<int> q = new Queue<int>();
            for (int x = 0; x < w; x++) { Seed(x, 0, q); Seed(x, h - 1, q); }
            for (int y = 0; y < h; y++) { Seed(0, y, q); Seed(w - 1, y, q); }

            while (q.Count > 0)
            {
                int idx = q.Dequeue();
                int x = idx % w, y = idx / w;
                if (x > 0) Seed(x - 1, y, q);
                if (x < w - 1) Seed(x + 1, y, q);
                if (y > 0) Seed(x, y - 1, q);
                if (y < h - 1) Seed(x, y + 1, q);
            }

            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int i = y * stride + x * 4;
                    if (bg[y * w + x]) { buf[i + 3] = 0; continue; }
                    if (NearBg(x, y))
                    {
                        int b = buf[i], g = buf[i + 1], r = buf[i + 2];
                        int lum = (r * 77 + g * 151 + b * 28) >> 8;
                        int a = 255;
                        if (lum >= 240) a = 0;
                        else if (lum > 226) a = (240 - lum) * 255 / 14;
                        if (a < buf[i + 3]) buf[i + 3] = (byte)a;
                    }
                }
            }

            Marshal.Copy(buf, 0, data.Scan0, len);
            bmp.UnlockBits(data);

            int minX = w, minY = h, maxX = -1, maxY = -1;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    if (buf[y * stride + x * 4 + 3] > 8)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            if (maxX < 0) { minX = 0; minY = 0; maxX = w - 1; maxY = h - 1; }
            int pad = 6;
            minX = Math.Max(0, minX - pad); minY = Math.Max(0, minY - pad);
            maxX = Math.Min(w - 1, maxX + pad); maxY = Math.Min(h - 1, maxY + pad);
            Rectangle crop = new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);

            using (Bitmap outb = new Bitmap(crop.Width, crop.Height, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(outb))
                {
                    g.CompositingMode = CompositingMode.SourceCopy;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.DrawImage(bmp, new Rectangle(0, 0, crop.Width, crop.Height), crop, GraphicsUnit.Pixel);
                }
                outb.Save(dst, ImageFormat.Png);
            }
            return crop.Width + "x" + crop.Height;
        }
    }

    static void Seed(int x, int y, Queue<int> q)
    {
        int idx = y * w + x;
        if (bg[idx]) return;
        int i = y * stride + x * 4;
        int b = buf[i], g = buf[i + 1], r = buf[i + 2];
        int mn = Math.Min(r, Math.Min(g, b));
        int mx = Math.Max(r, Math.Max(g, b));
        if (mn < 225 || (mx - mn) > 18) return;
        bg[idx] = true;
        q.Enqueue(idx);
    }

    static bool NearBg(int x, int y)
    {
        if (x > 0 && bg[y * w + x - 1]) return true;
        if (x < w - 1 && bg[y * w + x + 1]) return true;
        if (y > 0 && bg[(y - 1) * w + x]) return true;
        if (y < h - 1 && bg[(y + 1) * w + x]) return true;
        return false;
    }
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

$out = [BgCut]::Run((Resolve-Path $Src).Path, $Dst)
$f = Get-Item $Dst
"{0}  {1}  {2} KB" -f $f.Name, $out, [int]($f.Length / 1024)
