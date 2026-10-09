// RF4 Backup Tool – UI-Bausteine (WinForms, selbst gezeichnet: scharf bei jeder DPI, theme-fähig).
// Wird von build.ps1 in rf4sa-backup-gui.ps1 eingebettet und per Add-Type kompiliert (C# 5!).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Rf4Ui
{
    public static class UiTheme
    {
        public static Color Bg = Color.Black, Surface = Color.Black, Surface2 = Color.Black, Border = Color.Gray, Text = Color.White, Muted = Color.Gray;
        public static Color Accent = Color.Orange, AccentHover = Color.Orange, AccentText = Color.Black, Success = Color.Green, Warn = Color.Yellow, Danger = Color.Red, Selection = Color.Navy;
        public static bool Dark = true;

        public static Color Hex(string s)
        {
            s = s.TrimStart('#');
            return Color.FromArgb(Convert.ToInt32(s.Substring(0, 2), 16), Convert.ToInt32(s.Substring(2, 2), 16), Convert.ToInt32(s.Substring(4, 2), 16));
        }
        public static Color Mix(Color a, Color b, float t)
        {
            return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
        public static Color Kind(string kind)
        {
            switch (kind)
            {
                case "ok": return Success;
                case "warn": return Warn;
                case "danger": return Danger;
                case "accent": return Accent;
                default: return Muted;
            }
        }
        public static void Invalidate(Control c)
        {
            c.Invalidate();
            foreach (Control ch in c.Controls) Invalidate(ch);
        }
    }

    public static class Native
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);
        // dunkle bzw. helle Scrollbars (Win10 1809+)
        public static void DarkScroll(IntPtr h, bool dark) { try { SetWindowTheme(h, dark ? "DarkMode_Explorer" : "Explorer", null); } catch { } }

        public static void EnableDpi()
        {
            try { if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) SetProcessDPIAware(); }
            catch { try { SetProcessDPIAware(); } catch { } }
        }
        // dunkle Titelleiste (Win10 1809+/Win11) + Titelleistenfarbe passend zum Hintergrund (Win11)
        public static void TitleBar(IntPtr h, bool dark, Color caption, Color text)
        {
            try
            {
                int d = dark ? 1 : 0;
                if (DwmSetWindowAttribute(h, 20, ref d, 4) != 0) DwmSetWindowAttribute(h, 19, ref d, 4);
                int c = caption.R | (caption.G << 8) | (caption.B << 16);
                DwmSetWindowAttribute(h, 35, ref c, 4);
                int t = text.R | (text.G << 8) | (text.B << 16);
                DwmSetWindowAttribute(h, 36, ref t, 4);
            }
            catch { }
        }
    }

    public static class Gfx
    {
        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = Math.Max(0.01f, Math.Min(rad * 2f, Math.Min(r.Width, r.Height)));
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        static PointF P(RectangleF r, float x, float y) { return new PointF(r.X + r.Width * x, r.Y + r.Height * y); }

        public static void Icon(Graphics g, string kind, RectangleF r, Color c, float w)
        {
            SmoothingMode old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(c, w))
            using (SolidBrush br = new SolidBrush(c))
            {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                switch (kind)
                {
                    case "backup":
                        g.DrawLines(pen, new PointF[] { P(r, .15f, .58f), P(r, .15f, .86f), P(r, .85f, .86f), P(r, .85f, .58f) });
                        g.DrawLine(pen, P(r, .5f, .1f), P(r, .5f, .64f));
                        g.DrawLines(pen, new PointF[] { P(r, .3f, .48f), P(r, .5f, .66f), P(r, .7f, .48f) });
                        break;
                    case "restore":
                        g.DrawLines(pen, new PointF[] { P(r, .15f, .58f), P(r, .15f, .86f), P(r, .85f, .86f), P(r, .85f, .58f) });
                        g.DrawLine(pen, P(r, .5f, .66f), P(r, .5f, .12f));
                        g.DrawLines(pen, new PointF[] { P(r, .3f, .3f), P(r, .5f, .1f), P(r, .7f, .3f) });
                        break;
                    case "merge":
                        g.DrawLine(pen, P(r, .18f, .1f), P(r, .5f, .46f));
                        g.DrawLine(pen, P(r, .82f, .1f), P(r, .5f, .46f));
                        g.DrawLine(pen, P(r, .5f, .46f), P(r, .5f, .88f));
                        g.DrawLines(pen, new PointF[] { P(r, .32f, .72f), P(r, .5f, .9f), P(r, .68f, .72f) });
                        break;
                    case "sync":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f);
                            g.DrawArc(pen, a, 200, 130);
                            g.DrawArc(pen, a, 20, 130);
                            ArrowHead(g, pen, a, 330);
                            ArrowHead(g, pen, a, 150);
                        }
                        break;
                    case "globe":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .1f, r.Y + r.Height * .1f, r.Width * .8f, r.Height * .8f);
                            g.DrawEllipse(pen, a);
                            g.DrawEllipse(pen, new RectangleF(a.X + a.Width * .3f, a.Y, a.Width * .4f, a.Height));
                            g.DrawLine(pen, P(r, .1f, .5f), P(r, .9f, .5f));
                        }
                        break;
                    case "sun":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .32f, r.Y + r.Height * .32f, r.Width * .36f, r.Height * .36f);
                            g.DrawEllipse(pen, a);
                            for (int i = 0; i < 8; i++)
                            {
                                double an = i * Math.PI / 4;
                                float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
                                float r1 = r.Width * .30f, r2 = r.Width * .46f;
                                g.DrawLine(pen, cx + (float)Math.Cos(an) * r1, cy + (float)Math.Sin(an) * r1, cx + (float)Math.Cos(an) * r2, cy + (float)Math.Sin(an) * r2);
                            }
                        }
                        break;
                    case "moon":
                        {
                            using (GraphicsPath p1 = new GraphicsPath())
                            using (GraphicsPath p2 = new GraphicsPath())
                            {
                                p1.AddEllipse(new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f));
                                p2.AddEllipse(new RectangleF(r.X + r.Width * .36f, r.Y + r.Height * .04f, r.Width * .66f, r.Height * .66f));
                                using (Region rg = new Region(p1)) { rg.Exclude(p2); g.FillRegion(br, rg); }
                            }
                        }
                        break;
                    case "auto":
                        {
                            RectangleF a = new RectangleF(r.X + r.Width * .14f, r.Y + r.Height * .14f, r.Width * .72f, r.Height * .72f);
                            g.DrawEllipse(pen, a);
                            g.FillPie(br, Rectangle.Round(a), 270, 180);
                        }
                        break;
                    case "chevron":
                        g.DrawLines(pen, new PointF[] { P(r, .25f, .38f), P(r, .5f, .64f), P(r, .75f, .38f) });
                        break;
                    case "check":
                        g.DrawLines(pen, new PointF[] { P(r, .18f, .52f), P(r, .42f, .76f), P(r, .84f, .26f) });
                        break;
                    case "folder":
                        g.DrawLines(pen, new PointF[] { P(r, .1f, .26f), P(r, .1f, .8f), P(r, .9f, .8f), P(r, .9f, .34f), P(r, .46f, .34f), P(r, .38f, .22f), P(r, .1f, .22f), P(r, .1f, .26f) });
                        break;
                    case "disk":
                        g.DrawRectangle(pen, r.X + r.Width * .16f, r.Y + r.Height * .1f, r.Width * .68f, r.Height * .8f);
                        g.DrawLine(pen, P(r, .16f, .36f), P(r, .84f, .36f));
                        g.DrawEllipse(pen, r.X + r.Width * .38f, r.Y + r.Height * .5f, r.Width * .24f, r.Height * .24f);
                        break;
                }
            }
            g.SmoothingMode = old;
        }
        static void ArrowHead(Graphics g, Pen pen, RectangleF a, float angleDeg)
        {
            double an = angleDeg * Math.PI / 180.0;
            float cx = a.X + a.Width / 2, cy = a.Y + a.Height / 2, rad = a.Width / 2;
            PointF p = new PointF(cx + (float)Math.Cos(an) * rad, cy + (float)Math.Sin(an) * rad);
            double tx = -Math.Sin(an), ty = Math.Cos(an);   // Tangente im Uhrzeigersinn
            float h = a.Width * .30f;
            for (int s = -1; s <= 1; s += 2)
            {
                double rot = s * 0.75;
                double dx = -(tx * Math.Cos(rot) - ty * Math.Sin(rot)), dy = -(tx * Math.Sin(rot) + ty * Math.Cos(rot));
                g.DrawLine(pen, p, new PointF(p.X + (float)dx * h, p.Y + (float)dy * h));
            }
        }
    }

    // ── Button ────────────────────────────────────────────────────────────────
    public class UButton : Control
    {
        public string Kind = "secondary";   // primary | secondary | ghost
        public string IconKind = "";
        public bool ShowChevron = false;
        public float Dpi = 1f;
        bool hover, down;
        public UButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.StandardClick | ControlStyles.UseTextForAccessibility, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void PerformClick() { if (Enabled) OnClick(EventArgs.Empty); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Focus(); Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Enter || k == Keys.Space || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { PerformClick(); e.Handled = true; }
            base.OnKeyDown(e);
        }
        public Size Measure()
        {
            Size t = TextRenderer.MeasureText(Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            int w = t.Width + (int)(32 * Dpi);
            if (IconKind != "") w += (int)(t.Height * 1.2f) + (int)(8 * Dpi);
            if (ShowChevron) w += (int)(t.Height * .9f) + (int)(6 * Dpi);
            return new Size(w, t.Height + (int)(18 * Dpi));
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color parent = Parent != null ? Parent.BackColor : UiTheme.Bg;
            using (SolidBrush pb = new SolidBrush(parent)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            float rad = 9f * Dpi;
            Color fill, fore, border = Color.Empty;
            bool en = Enabled;
            if (Kind == "primary")
            {
                fill = !en ? UiTheme.Mix(UiTheme.Surface2, UiTheme.Bg, .3f) : (down ? UiTheme.Mix(UiTheme.Accent, Color.Black, .14f) : (hover ? UiTheme.AccentHover : UiTheme.Accent));
                fore = en ? UiTheme.AccentText : UiTheme.Muted;
            }
            else if (Kind == "ghost")
            {
                fill = (hover || down) && en ? UiTheme.Surface2 : Color.Empty;
                fore = en ? UiTheme.Text : UiTheme.Muted;
            }
            else
            {
                fill = !en ? UiTheme.Surface : (down ? UiTheme.Mix(UiTheme.Surface2, UiTheme.Border, .5f) : (hover ? UiTheme.Surface2 : UiTheme.Surface));
                fore = en ? UiTheme.Text : UiTheme.Muted;
                border = UiTheme.Border;
            }
            using (GraphicsPath p = Gfx.Round(rc, rad))
            {
                if (fill != Color.Empty) using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                if (border != Color.Empty) using (Pen pn = new Pen(border, 1f)) g.DrawPath(pn, p);
                if (Focused && ShowFocusCues) using (Pen fp = new Pen(UiTheme.Accent, 2f * Dpi)) { RectangleF fr = RectangleF.Inflate(rc, -2f * Dpi, -2f * Dpi); using (GraphicsPath fpth = Gfx.Round(fr, rad - 2f * Dpi)) g.DrawPath(fp, fpth); }
            }
            Size ts = TextRenderer.MeasureText(g, Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            float ih = ts.Height * 1.1f;
            float total = ts.Width;
            if (IconKind != "") total += ih + 8f * Dpi;
            if (ShowChevron) total += ih * .8f + 6f * Dpi;
            float avail = Width - 20f * Dpi;
            float x = (Width - Math.Min(total, avail)) / 2f;
            float cy = Height / 2f;
            if (IconKind != "") { Gfx.Icon(g, IconKind, new RectangleF(x, cy - ih / 2f, ih, ih), fore, Math.Max(1.5f, 1.6f * Dpi)); x += ih + 8f * Dpi; }
            Rectangle tr = new Rectangle((int)x, 0, (int)Math.Max(10, avail - (x - (Width - avail) / 2f) - (ShowChevron ? ih : 0)), Height);
            TextRenderer.DrawText(g, Text, Font, tr, fore, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            if (ShowChevron) Gfx.Icon(g, "chevron", new RectangleF(Math.Min(x + ts.Width + 6f * Dpi, Width - 14f * Dpi - ih * .8f), cy - ih * .4f, ih * .8f, ih * .8f), fore, Math.Max(1.5f, 1.6f * Dpi));
        }
    }

    // ── Karte (Text, Icon, Badge; auswählbar) ─────────────────────────────────
    public class UCard : Control
    {
        public string Title = "", Sub = "", Badge = "", BadgeKind = "muted", IconKind = "";
        public bool Selected, Hovered, Clickable = true, ShowCheck, Dim, IconTop;
        public Font TitleFont, SubFont, BadgeFont;
        public float Dpi = 1f;
        public object Tag2;
        public UCard()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable | ControlStyles.StandardClick, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void PerformClick() { OnClick(EventArgs.Empty); }
        protected override void OnMouseEnter(EventArgs e) { Hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { Hovered = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Space || k == Keys.Enter || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { OnClick(EventArgs.Empty); e.Handled = true; }
            base.OnKeyDown(e);
        }
        protected override void OnMouseDown(MouseEventArgs e) { Focus(); base.OnMouseDown(e); }

        const TextFormatFlags TF = TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.WordBreak | TextFormatFlags.Left | TextFormatFlags.Top;
        void Areas(out Rectangle icon, out Rectangle text, out Rectangle badge, Graphics g)
        {
            int pad = (int)(14 * Dpi);
            int x = pad;
            icon = Rectangle.Empty;
            if (ShowCheck) { x += (int)(26 * Dpi); }
            if (IconKind != "") { int d = (int)(Math.Min(Height - 2 * pad + 8 * Dpi, 56 * Dpi)); icon = new Rectangle(x, IconTop ? pad : (Height - d) / 2, d, d); x += d + (int)(14 * Dpi); }
            badge = Rectangle.Empty;
            int right = Width - pad;
            if (Badge != "" && BadgeFont != null)
            {
                Size bs = TextRenderer.MeasureText(g, Badge, BadgeFont, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                int bw = bs.Width + (int)(20 * Dpi), bh = bs.Height + (int)(8 * Dpi);
                badge = new Rectangle(Width - pad - bw, pad - (int)(2 * Dpi), bw, bh);
                right = badge.X - (int)(10 * Dpi);
            }
            text = new Rectangle(x, pad - (int)(2 * Dpi), Math.Max(10, right - x), Height - 2 * pad + (int)(4 * Dpi));
        }
        // Prüft, ob Titel (einzeilig) bzw. Untertitel (im verfügbaren Platz) abgeschnitten würden
        public bool Overflows()
        {
            using (Graphics g = CreateGraphics())
            {
                Rectangle ic, tx, bd; Areas(out ic, out tx, out bd, g);
                Font tf = TitleFont ?? Font; Font sf = SubFont ?? Font;
                Size t = TextRenderer.MeasureText(g, Title, tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                if (t.Width > tx.Width) return true;
                if (Sub != "")
                {
                    int th = TextRenderer.MeasureText(g, "Ag", tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height + (int)(4 * Dpi);
                    Size s = TextRenderer.MeasureText(g, Sub, sf, new Size(tx.Width, 0), TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                    if (s.Height > tx.Height - th + (int)(4 * Dpi)) return true;
                }
            }
            return false;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color parent = Parent != null ? Parent.BackColor : UiTheme.Bg;
            using (SolidBrush pb = new SolidBrush(parent)) g.FillRectangle(pb, ClientRectangle);
            float bw = Selected ? 2f * Dpi : 1f;
            RectangleF rc = new RectangleF(bw / 2f, bw / 2f, Width - bw - 0.5f, Height - bw - 0.5f);
            Color fill = Selected ? UiTheme.Selection : ((Hovered && Clickable) ? UiTheme.Surface2 : UiTheme.Surface);
            Color border = Selected ? UiTheme.Accent : ((Hovered && Clickable) ? UiTheme.Mix(UiTheme.Border, UiTheme.Accent, .35f) : UiTheme.Border);
            using (GraphicsPath p = Gfx.Round(rc, 12f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(fill)) g.FillPath(b, p);
                using (Pen pn = new Pen(border, bw)) g.DrawPath(pn, p);
            }
            if (Focused && ShowFocusCues)
                using (Pen fp = new Pen(UiTheme.Accent, 1.5f * Dpi)) { fp.DashStyle = DashStyle.Dot; using (GraphicsPath fpth = Gfx.Round(RectangleF.Inflate(rc, -4f * Dpi, -4f * Dpi), 9f * Dpi)) g.DrawPath(fp, fpth); }

            Rectangle ic, tx, bd; Areas(out ic, out tx, out bd, g);
            Color titleCol = Dim ? UiTheme.Muted : UiTheme.Text;
            if (ShowCheck)
            {
                int d = (int)(18 * Dpi); int cx = (int)(14 * Dpi); int cy = (Height - d) / 2;
                RectangleF box = new RectangleF(cx, cy, d, d);
                using (GraphicsPath bp = Gfx.Round(box, 5f * Dpi))
                {
                    if (Selected) { using (SolidBrush ab = new SolidBrush(UiTheme.Accent)) g.FillPath(ab, bp); Gfx.Icon(g, "check", box, UiTheme.AccentText, 2f * Dpi); }
                    else using (Pen bpn = new Pen(UiTheme.Muted, 1.5f * Dpi)) g.DrawPath(bpn, bp);
                }
            }
            if (!ic.IsEmpty)
            {
                using (SolidBrush cb = new SolidBrush(Selected ? UiTheme.Accent : UiTheme.Surface2)) g.FillEllipse(cb, ic);
                float pad = ic.Width * .24f;
                Gfx.Icon(g, IconKind, new RectangleF(ic.X + pad, ic.Y + pad, ic.Width - 2 * pad, ic.Height - 2 * pad), Selected ? UiTheme.AccentText : (Dim ? UiTheme.Muted : UiTheme.Accent), Math.Max(1.6f, 1.9f * Dpi));
            }
            Font tf = TitleFont ?? Font; Font sf = SubFont ?? Font;
            int th = TextRenderer.MeasureText(g, "Ag", tf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height;
            TextRenderer.DrawText(g, Title, tf, new Rectangle(tx.X, tx.Y, tx.Width, th + 2), titleCol, TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine | TextFormatFlags.Left | TextFormatFlags.Top);
            if (Sub != "")
                TextRenderer.DrawText(g, Sub, sf, new Rectangle(tx.X, tx.Y + th + (int)(4 * Dpi), tx.Width, Math.Max(10, tx.Height - th - (int)(4 * Dpi))), UiTheme.Muted, TF);
            if (!bd.IsEmpty)
            {
                Color kc = UiTheme.Kind(BadgeKind);
                using (GraphicsPath bp = Gfx.Round(bd, bd.Height / 2f))
                {
                    using (SolidBrush bb = new SolidBrush(UiTheme.Mix(fill, kc, .18f))) g.FillPath(bb, bp);
                    using (Pen bpn = new Pen(UiTheme.Mix(fill, kc, .55f), 1f)) g.DrawPath(bpn, bp);
                }
                TextRenderer.DrawText(g, Badge, BadgeFont, bd, kc, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }
        }
    }

    // ── Liste aus Karten ──────────────────────────────────────────────────────
    public class UCardList : Panel
    {
        public List<UCard> Cards = new List<UCard>();
        public string Mode = "one";          // none | one | multi
        public float Dpi = 1f;
        public int CardHeight = 64, Gap = 8;
        public Font TitleFont, SubFont, BadgeFont;
        public event EventHandler SelectionChanged;
        public UCardList()
        {
            AutoScroll = true; DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }
        public UCard Add(string title, string sub, string badge, string badgeKind, string icon, object tag)
        {
            UCard c = new UCard();
            c.Title = title; c.Sub = sub; c.Badge = badge; c.BadgeKind = badgeKind; c.IconKind = icon; c.Tag2 = tag;
            c.Dpi = Dpi; c.TitleFont = TitleFont; c.SubFont = SubFont; c.BadgeFont = BadgeFont; c.Font = SubFont ?? Font;
            c.ShowCheck = (Mode == "multi"); c.Clickable = (Mode != "none"); c.Cursor = Mode == "none" ? Cursors.Default : Cursors.Hand;
            c.Click += CardClick;
            Cards.Add(c); Controls.Add(c);
            LayoutCards();
            return c;
        }
        public void ClearItems() { foreach (UCard c in Cards) { Controls.Remove(c); c.Dispose(); } Cards.Clear(); }
        void CardClick(object s, EventArgs e)
        {
            UCard c = (UCard)s;
            if (Mode == "none") return;
            if (Mode == "one") { foreach (UCard o in Cards) o.Selected = (o == c); }
            else c.Selected = !c.Selected;
            foreach (UCard o in Cards) o.Invalidate();
            if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
        }
        public int SelectedIndex
        {
            get { for (int i = 0; i < Cards.Count; i++) if (Cards[i].Selected) return i; return -1; }
            set
            {
                for (int i = 0; i < Cards.Count; i++) Cards[i].Selected = (i == value);
                foreach (UCard o in Cards) o.Invalidate();
                if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
            }
        }
        public int[] SelectedIndices
        {
            get { List<int> l = new List<int>(); for (int i = 0; i < Cards.Count; i++) if (Cards[i].Selected) l.Add(i); return l.ToArray(); }
        }
        public void SetSelected(int i, bool sel) { if (i >= 0 && i < Cards.Count) { Cards[i].Selected = sel; Cards[i].Invalidate(); } }
        public int ContentHeight { get { return Cards.Count * (CardHeight + Gap); } }
        public void LayoutCards()
        {
            SuspendLayout();
            int w = ClientSize.Width;
            int y = 0;
            foreach (UCard c in Cards) { c.SetBounds(0, y, Math.Max(10, w), CardHeight); y += CardHeight + Gap; }
            AutoScrollMinSize = new Size(0, Math.Max(0, y - Gap));
            try { VerticalScroll.SmallChange = Math.Max(20, CardHeight / 2); VerticalScroll.LargeChange = Math.Max(60, CardHeight * 2); } catch { }
            ResumeLayout(false);
        }
        protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutCards(); }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Native.DarkScroll(Handle, UiTheme.Dark); }
    }

    // ── Schritt-Anzeige ───────────────────────────────────────────────────────
    public class UStepper : Control
    {
        public string[] Steps = new string[0];
        public int Current = 0;
        public float Dpi = 1f;
        public UStepper() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            int n = Steps.Length; if (n == 0) return;
            float d = 24f * Dpi, slot = (float)Width / n, cy = d / 2f + 6f * Dpi;
            for (int i = 0; i < n - 1; i++)
            {
                float x1 = slot * i + slot / 2f + d / 2f + 4f * Dpi, x2 = slot * (i + 1) + slot / 2f - d / 2f - 4f * Dpi;
                using (Pen p = new Pen(i < Current ? UiTheme.Success : UiTheme.Border, 2f * Dpi)) g.DrawLine(p, x1, cy, x2, cy);
            }
            for (int i = 0; i < n; i++)
            {
                float cx = slot * i + slot / 2f;
                RectangleF c = new RectangleF(cx - d / 2f, cy - d / 2f, d, d);
                bool done = i < Current, cur = i == Current;
                using (SolidBrush b = new SolidBrush(done ? UiTheme.Success : (cur ? UiTheme.Accent : UiTheme.Surface2))) g.FillEllipse(b, c);
                if (!done && !cur) using (Pen p = new Pen(UiTheme.Border, 1f)) g.DrawEllipse(p, c);
                if (done) Gfx.Icon(g, "check", new RectangleF(c.X + 4 * Dpi, c.Y + 4 * Dpi, c.Width - 8 * Dpi, c.Height - 8 * Dpi), UiTheme.AccentText, 2f * Dpi);
                else TextRenderer.DrawText(g, (i + 1).ToString(), Font, Rectangle.Round(c), cur ? UiTheme.AccentText : UiTheme.Muted, TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
                Rectangle lr = new Rectangle((int)(slot * i), (int)(cy + d / 2f + 4f * Dpi), (int)slot, Height - (int)(cy + d / 2f + 4f * Dpi));
                using (Font f = new Font(Font, cur ? FontStyle.Bold : FontStyle.Regular))
                    TextRenderer.DrawText(g, Steps[i], f, lr, cur ? UiTheme.Text : (done ? UiTheme.Success : UiTheme.Muted), TextFormatFlags.NoPadding | TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            }
        }
    }

    // ── Checkbox ──────────────────────────────────────────────────────────────
    public class UCheck : Control
    {
        public bool Checked = false;
        public float Dpi = 1f;
        public event EventHandler CheckedChanged;
        public UCheck()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.Selectable | ControlStyles.StandardClick | ControlStyles.UseTextForAccessibility, true);
            TabStop = true; Cursor = Cursors.Hand;
        }
        public void Toggle() { Checked = !Checked; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); }
        protected override void OnClick(EventArgs e) { if (Enabled) Toggle(); base.OnClick(e); }
        protected override void OnMouseDown(MouseEventArgs e) { Focus(); base.OnMouseDown(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Space || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space) { Toggle(); e.Handled = true; } base.OnKeyDown(e); }
        public int PreferredWidth()
        {
            return TextRenderer.MeasureText(Text, Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Width + (int)(34 * Dpi);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            float d = 18f * Dpi; RectangleF box = new RectangleF(1f, (Height - d) / 2f, d, d);
            Color fore = Enabled ? UiTheme.Text : UiTheme.Muted;
            using (GraphicsPath bp = Gfx.Round(box, 5f * Dpi))
            {
                if (Checked) { using (SolidBrush ab = new SolidBrush(Enabled ? UiTheme.Accent : UiTheme.Mix(UiTheme.Accent, UiTheme.Bg, .6f))) g.FillPath(ab, bp); Gfx.Icon(g, "check", box, UiTheme.AccentText, 2f * Dpi); }
                else { using (SolidBrush sb = new SolidBrush(UiTheme.Surface)) g.FillPath(sb, bp); using (Pen pn = new Pen(Focused && ShowFocusCues ? UiTheme.Accent : UiTheme.Muted, 1.5f * Dpi)) g.DrawPath(pn, bp); }
            }
            TextRenderer.DrawText(g, Text, Font, new Rectangle((int)(d + 10f * Dpi), 0, Width - (int)(d + 10f * Dpi), Height), fore, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        }
    }

    // ── Eingabefeld ───────────────────────────────────────────────────────────
    public class UInput : Control
    {
        public TextBox Box = new TextBox();
        public float Dpi = 1f;
        bool focused;
        public UInput()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Box.BorderStyle = BorderStyle.None;
            Box.Enter += delegate { focused = true; Invalidate(); };
            Box.Leave += delegate { focused = false; Invalidate(); };
            Controls.Add(Box);
        }
        public override string Text { get { return Box.Text; } set { Box.Text = value; } }
        public void ApplyTheme() { Box.BackColor = UiTheme.Surface; Box.ForeColor = UiTheme.Text; Box.Font = Font; PositionBox(); Invalidate(); }
        void PositionBox()
        {
            int pad = (int)(12 * Dpi);
            Box.Font = Font;
            int h = Box.PreferredHeight;
            Box.SetBounds(pad, Math.Max(0, (Height - h) / 2), Math.Max(10, Width - 2 * pad), h);
        }
        protected override void OnResize(EventArgs e) { base.OnResize(e); PositionBox(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); PositionBox(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Gfx.Round(rc, 9f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(UiTheme.Surface)) g.FillPath(b, p);
                using (Pen pn = new Pen(focused ? UiTheme.Accent : UiTheme.Border, focused ? 1.6f * Dpi : 1f)) g.DrawPath(pn, p);
            }
        }
    }

    // ── Fortschrittsbalken ────────────────────────────────────────────────────
    public class UProgress : Control
    {
        public bool Indeterminate = true;
        public int Value = 0;     // 0..100
        public float Dpi = 1f;
        float phase = 0f;
        Timer timer = new Timer();
        public UProgress()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            timer.Interval = 30; timer.Tick += delegate { Step(); };
            timer.Start();
        }
        public void Step() { phase += 0.018f; if (phase > 1f) phase -= 1f; Invalidate(); }
        protected override void Dispose(bool disposing) { if (disposing) { timer.Stop(); timer.Dispose(); } base.Dispose(disposing); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF tr = new RectangleF(0, 0, Width - 1, Height - 1);
            using (GraphicsPath tp = Gfx.Round(tr, tr.Height / 2f)) using (SolidBrush tb = new SolidBrush(UiTheme.Surface2)) g.FillPath(tb, tp);
            RectangleF bar;
            if (Indeterminate)
            {
                float w = tr.Width * .32f, x = (tr.Width + w) * phase - w;
                float x0 = Math.Max(0, x), x1 = Math.Min(tr.Width, x + w);
                if (x1 <= x0) return;
                bar = new RectangleF(x0, 0, x1 - x0, tr.Height);
            }
            else bar = new RectangleF(0, 0, Math.Max(tr.Height, tr.Width * Value / 100f), tr.Height);
            using (GraphicsPath bp = Gfx.Round(bar, bar.Height / 2f)) using (SolidBrush bb = new SolidBrush(UiTheme.Accent)) g.FillPath(bb, bp);
        }
    }

    // ── Kennzahl-Kachel ───────────────────────────────────────────────────────
    public class UStat : Control
    {
        public string Value = "0", Caption = "", Kind = "muted";
        public Font ValueFont;
        public float Dpi = 1f;
        public UStat() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        public bool Overflows()
        {
            using (Graphics g = CreateGraphics())
            {
                Size c = TextRenderer.MeasureText(g, Caption, Font, new Size(Width - (int)(24 * Dpi), 0), TextFormatFlags.NoPadding | TextFormatFlags.WordBreak);
                Size v = TextRenderer.MeasureText(g, Value, ValueFont ?? Font, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
                return v.Width > Width - (int)(24 * Dpi) || (v.Height + c.Height + (int)(26 * Dpi)) > Height;
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (SolidBrush pb = new SolidBrush(Parent != null ? Parent.BackColor : UiTheme.Bg)) g.FillRectangle(pb, ClientRectangle);
            RectangleF rc = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            Color kc = UiTheme.Kind(Kind);
            using (GraphicsPath p = Gfx.Round(rc, 12f * Dpi))
            {
                using (SolidBrush b = new SolidBrush(UiTheme.Surface)) g.FillPath(b, p);
                using (Pen pn = new Pen(UiTheme.Border, 1f)) g.DrawPath(pn, p);
            }
            using (GraphicsPath ap = Gfx.Round(new RectangleF(0.5f, 0.5f, 5f * Dpi, Height - 1.5f), 3f * Dpi)) using (SolidBrush ab = new SolidBrush(kc)) g.FillPath(ab, ap);
            int pad = (int)(16 * Dpi);
            Font vf = ValueFont ?? Font;
            int vh = TextRenderer.MeasureText(g, "0", vf, new Size(int.MaxValue, 0), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine).Height;
            TextRenderer.DrawText(g, Value, vf, new Rectangle(pad, (int)(8 * Dpi), Width - pad - (int)(8 * Dpi), vh), kc, TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
            TextRenderer.DrawText(g, Caption, Font, new Rectangle(pad, (int)(8 * Dpi) + vh, Width - pad - (int)(8 * Dpi), Height - vh - (int)(12 * Dpi)), UiTheme.Muted, TextFormatFlags.NoPadding | TextFormatFlags.WordBreak | TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.EndEllipsis);
        }
    }

    // ── Menü-Darstellung (Sprach-/Design-Auswahl) ─────────────────────────────
    public class MenuColors : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientBegin { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientMiddle { get { return UiTheme.Surface; } }
        public override Color ImageMarginGradientEnd { get { return UiTheme.Surface; } }
        public override Color MenuBorder { get { return UiTheme.Border; } }
        public override Color MenuItemBorder { get { return UiTheme.Accent; } }
        public override Color MenuItemSelected { get { return UiTheme.Surface2; } }
        public override Color MenuItemSelectedGradientBegin { get { return UiTheme.Surface2; } }
        public override Color MenuItemSelectedGradientEnd { get { return UiTheme.Surface2; } }
        public override Color SeparatorDark { get { return UiTheme.Border; } }
        public override Color SeparatorLight { get { return UiTheme.Border; } }
        public override Color CheckBackground { get { return UiTheme.Selection; } }
        public override Color CheckSelectedBackground { get { return UiTheme.Selection; } }
        public override Color CheckPressedBackground { get { return UiTheme.Selection; } }
    }
    public class ThemedRenderer : ToolStripProfessionalRenderer
    {
        public ThemedRenderer() : base(new MenuColors()) { RoundedEdges = false; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) { e.TextColor = UiTheme.Text; base.OnRenderItemText(e); }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) { e.ArrowColor = UiTheme.Text; base.OnRenderArrow(e); }
    }

    // Mausrad: Nachricht an das Steuerelement UNTER dem Mauszeiger leiten (WinForms schickt sie sonst an das fokussierte)
    public class WheelFilter : IMessageFilter
    {
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        static bool installed;
        public static void Install() { if (!installed) { Application.AddMessageFilter(new WheelFilter()); installed = true; } }
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != 0x020A) return false;
            long lp = m.LParam.ToInt64();
            Point p = new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF));
            IntPtr h = WindowFromPoint(p);
            if (h != IntPtr.Zero && h != m.HWnd && Control.FromHandle(h) != null) { SendMessage(h, m.Msg, m.WParam, m.LParam); return true; }
            return false;
        }
    }
}