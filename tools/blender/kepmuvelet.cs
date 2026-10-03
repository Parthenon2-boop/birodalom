// Birodalom — képműveletek a mintalaphoz (PowerShell Add-Type-pal töltődik be).
// Csapatszínezés a maszkkal, nagyítás, kontaktlap-összerakás.
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class Kep
{
    public static Bitmap Load(string p)
    {
        using (var b = new Bitmap(p)) { return new Bitmap(b); }
    }

    static byte[] Bytes(Bitmap b, out BitmapData d)
    {
        d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        var arr = new byte[d.Stride * b.Height];
        Marshal.Copy(d.Scan0, arr, 0, arr.Length);
        return arr;
    }

    static void Put(Bitmap b, BitmapData d, byte[] arr)
    {
        Marshal.Copy(arr, 0, d.Scan0, arr.Length);
        b.UnlockBits(d);
    }

    // A játék árnyalójának megfelelője:
    //   rgb = mix(rgb, rgb * csapat * 1.6, m.r) ; rgb = mix(rgb, rgb * kiemelo * 1.5, m.g)
    public static Bitmap Tint(Bitmap col, Bitmap mask, Color team, Color acc)
    {
        return Tint(col, mask, team, acc, Color.FromArgb(0x93, 0x37, 0x2a));
    }

    // A tető (maszk B) a nemzeti tetőszínt kapja: rgb = mix(rgb, rgb * teto * 2.0, m.b)
    public static Bitmap Tint(Bitmap col, Bitmap mask, Color team, Color acc, Color roof)
    {
        var o = new Bitmap(col.Width, col.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(o)) g.DrawImage(col, 0, 0, col.Width, col.Height);
        if (mask == null) return o;
        BitmapData d1, d2;
        var a = Bytes(o, out d1);
        var m = Bytes(mask, out d2);
        double tr = team.R / 255.0 * 1.6, tg = team.G / 255.0 * 1.6, tb = team.B / 255.0 * 1.6;
        double ar = acc.R / 255.0 * 1.5, ag = acc.G / 255.0 * 1.5, ab = acc.B / 255.0 * 1.5;
        double rr = roof.R / 255.0 * 2.0, rg = roof.G / 255.0 * 2.0, rb = roof.B / 255.0 * 2.0;
        for (int y = 0; y < o.Height; y++)
            for (int x = 0; x < o.Width; x++)
            {
                int i = y * d1.Stride + x * 4;
                int j = y * d2.Stride + x * 4;
                double mr = m[j + 2] / 255.0, mg = m[j + 1] / 255.0, mb = m[j] / 255.0;
                double b = a[i], gg = a[i + 1], r = a[i + 2];
                r = r * (1 - mr) + r * tr * mr; gg = gg * (1 - mr) + gg * tg * mr; b = b * (1 - mr) + b * tb * mr;
                r = r * (1 - mg) + r * ar * mg; gg = gg * (1 - mg) + gg * ag * mg; b = b * (1 - mg) + b * ab * mg;
                r = r * (1 - mb) + r * rr * mb; gg = gg * (1 - mb) + gg * rg * mb; b = b * (1 - mb) + b * rb * mb;
                a[i + 2] = (byte)Math.Min(255, r); a[i + 1] = (byte)Math.Min(255, gg); a[i] = (byte)Math.Min(255, b);
            }
        mask.UnlockBits(d2);
        Put(o, d1, a);
        return o;
    }

    public static Graphics G(Bitmap b)
    {
        var g = Graphics.FromImage(b);
        g.CompositingMode = CompositingMode.SourceOver;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        return g;
    }

    // Kép rárajzolása; scale < 1: jó minőségű kicsinyítés (a játék mipmapes
    // szűrését közelíti), scale > 1: legközelebbi szomszéd (képpontok látszanak).
    public static void Draw(Graphics g, Bitmap src, float x, float y, float scale, bool smoothUp)
    {
        var st = g.Save();
        if (scale < 1f || smoothUp)
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        }
        else g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.DrawImage(src, new RectangleF(x, y, src.Width * scale, src.Height * scale));
        g.Restore(st);
    }

    public static void Text(Graphics g, string s, float x, float y, float size, Color c)
    {
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using (var f = new Font("Segoe UI", size, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var sh = new SolidBrush(Color.FromArgb(160, 0, 0, 0)))
        using (var br = new SolidBrush(c))
        {
            g.DrawString(s, f, sh, x + 1, y + 1);
            g.DrawString(s, f, br, x, y);
        }
    }

    // Fűszerű, enyhén foltos háttér (a játék talajszínéhez).
    public static Bitmap Grass(int w, int h, int seed)
    {
        var o = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData d;
        var a = Bytes(o, out d);
        var rnd = new Random(seed);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                double n = Math.Sin(x * 0.013 + Math.Sin(y * 0.009) * 2) * 0.5 + Math.Sin(y * 0.017 + x * 0.004) * 0.5;
                double k = rnd.NextDouble() * 0.06;
                int i = y * d.Stride + x * 4;
                double r = 104 + n * 12 + k * 255 * 0.2, gg = 150 + n * 16 + k * 255 * 0.3, b = 62 + n * 6;
                a[i + 2] = (byte)r; a[i + 1] = (byte)gg; a[i] = (byte)b; a[i + 3] = 255;
            }
        Put(o, d, a);
        return o;
    }
}
