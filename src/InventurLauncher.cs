// Netixx Windows Inventory: grafischer Starter fuer Invoke-Inventur.ps1
//
// Bewusst in C# 5 geschrieben (keine String-Interpolation, kein ?.), damit der
// in Windows mitgelieferte .NET-Framework-Compiler (csc.exe v4.0.30319) es baut.
// Das PowerShell-Skript ist als Ressource eingebettet und wird zur Laufzeit in
// einen Temp-Ordner geschrieben und mit Windows PowerShell 5.1 ausgefuehrt.

using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Netixx Windows Inventory")]
[assembly: AssemblyDescription("Inventur eines Windows-10/11-Rechners als Markdown-Report")]
[assembly: AssemblyCompany("Netixx IT Solutions")]
[assembly: AssemblyProduct("Netixx Windows Inventory")]
[assembly: AssemblyCopyright("© 2026 Netixx IT Solutions")]
[assembly: AssemblyVersion("0.8.2.0")]
[assembly: AssemblyFileVersion("0.8.2.0")]

namespace WinInventory
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    class MainForm : Form
    {
        const string ResourceName = "Invoke-Inventur.ps1";
        const string SettingsKey = @"Software\win-inventory";
        const string Website = "www.netixx.it";

        TextBox txtKunde, txtTechniker, txtOrdner, txtLog;
        CheckBox chkStore, chkKey;
        Button btnStart, btnBrowse, btnOpen, btnFolder;
        ProgressBar progress;
        Label lblStatus;

        Process proc;
        string tempScript;
        string reportPath;

        public MainForm()
        {
            // Alle Pixelangaben gelten fuer 96 DPI (100 %). Ohne AutoScaleDimensions
            // skaliert WinForms nichts, und bei 125/150 % waere das Fenster zu klein
            // fuer die mitwachsende Schrift.
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Netixx Windows Inventory – " + Environment.MachineName;
            Font = SystemFonts.MessageBoxFont;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(620, 520);
            MinimumSize = new Size(520, 440);
            BuildLayout();
            ResumeLayout(false);
            PerformLayout();

            txtTechniker.Text = LoadSetting("Techniker");
            txtOrdner.Text = DefaultFolder();
            AcceptButton = btnStart;
            FormClosing += OnFormClosing;
        }

        // -------------------------------------------------------------------
        // Oberflaeche
        // -------------------------------------------------------------------

        void BuildLayout()
        {
            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.Padding = new Padding(12);
            t.ColumnCount = 3;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            Label intro = new Label();
            intro.Text = "Erfasst Hardware, Sicherheit, Benutzer, Lizenz und installierte Software " +
                         "dieses Rechners und speichert alles als Markdown-Report.";
            intro.AutoSize = true;
            intro.MaximumSize = new Size(580, 0);
            intro.Margin = new Padding(3, 0, 3, 12);
            t.Controls.Add(intro, 0, 0);
            t.SetColumnSpan(intro, 3);

            txtKunde = new TextBox();
            AddRow(t, 1, "Kunde:", txtKunde, null);

            txtTechniker = new TextBox();
            AddRow(t, 2, "Techniker:", txtTechniker, null);

            txtOrdner = new TextBox();
            btnBrowse = new Button();
            btnBrowse.Text = "Durchsuchen…";
            btnBrowse.AutoSize = true;
            btnBrowse.Click += OnBrowse;
            AddRow(t, 3, "Speichern in:", txtOrdner, btnBrowse);

            chkStore = new CheckBox();
            chkStore.Text = "Store-Apps auflisten";
            chkStore.Checked = true;
            chkStore.AutoSize = true;
            t.Controls.Add(chkStore, 1, 4);
            t.SetColumnSpan(chkStore, 2);

            chkKey = new CheckBox();
            chkKey.Text = "OEM-Produktschlüssel vollständig ausgeben (sonst maskiert)";
            chkKey.AutoSize = true;
            t.Controls.Add(chkKey, 1, 5);
            t.SetColumnSpan(chkKey, 2);

            btnStart = new Button();
            btnStart.Text = "Inventur starten";
            btnStart.AutoSize = true;
            btnStart.Padding = new Padding(10, 3, 10, 3);
            btnStart.Anchor = AnchorStyles.Right;
            btnStart.Margin = new Padding(3, 10, 3, 10);
            btnStart.Click += OnStart;
            t.Controls.Add(btnStart, 0, 6);
            t.SetColumnSpan(btnStart, 3);

            progress = new ProgressBar();
            progress.Style = ProgressBarStyle.Marquee;
            progress.MarqueeAnimationSpeed = 30;
            progress.Dock = DockStyle.Fill;
            progress.Visible = false;
            t.Controls.Add(progress, 0, 7);
            t.SetColumnSpan(progress, 3);

            txtLog = new TextBox();
            txtLog.Multiline = true;
            txtLog.ReadOnly = true;
            txtLog.ScrollBars = ScrollBars.Vertical;
            txtLog.Dock = DockStyle.Fill;
            txtLog.Font = new Font(FontFamily.GenericMonospace, Font.SizeInPoints);
            txtLog.BackColor = SystemColors.Window;
            t.Controls.Add(txtLog, 0, 8);
            t.SetColumnSpan(txtLog, 3);

            FlowLayoutPanel bottom = new FlowLayoutPanel();
            bottom.Dock = DockStyle.Fill;
            bottom.AutoSize = true;
            bottom.WrapContents = false;
            lblStatus = new Label();
            lblStatus.AutoSize = true;
            lblStatus.Margin = new Padding(3, 8, 12, 3);
            btnOpen = new Button();
            btnOpen.Text = "Report öffnen";
            btnOpen.AutoSize = true;
            btnOpen.Visible = false;
            btnOpen.Click += OnOpenReport;
            btnFolder = new Button();
            btnFolder.Text = "Ordner öffnen";
            btnFolder.AutoSize = true;
            btnFolder.Visible = false;
            btnFolder.Click += OnOpenFolder;
            bottom.Controls.Add(lblStatus);
            bottom.Controls.Add(btnOpen);
            bottom.Controls.Add(btnFolder);
            t.Controls.Add(bottom, 0, 9);
            t.SetColumnSpan(bottom, 3);

            TableLayoutPanel footer = new TableLayoutPanel();
            footer.Dock = DockStyle.Fill;
            footer.AutoSize = true;
            footer.Margin = new Padding(0, 6, 0, 0);
            footer.ColumnCount = 2;
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            Label lblVersion = new Label();
            lblVersion.Text = "Version " + Assembly.GetExecutingAssembly().GetName().Version.ToString(3) +
                              " · © 2026 Netixx IT Solutions";
            lblVersion.AutoSize = true;
            lblVersion.Anchor = AnchorStyles.Left;
            lblVersion.ForeColor = SystemColors.GrayText;
            footer.Controls.Add(lblVersion, 0, 0);

            string credit = "created for the people by ";
            LinkLabel lnkWebsite = new LinkLabel();
            lnkWebsite.Text = credit + Website;
            lnkWebsite.LinkArea = new LinkArea(credit.Length, Website.Length);
            lnkWebsite.AutoSize = true;
            lnkWebsite.Anchor = AnchorStyles.Right;
            lnkWebsite.ForeColor = SystemColors.GrayText;
            lnkWebsite.LinkClicked += OnWebsite;
            footer.Controls.Add(lnkWebsite, 1, 0);

            t.Controls.Add(footer, 0, 10);
            t.SetColumnSpan(footer, 3);

            t.RowCount = 11;
            for (int i = 0; i < t.RowCount; i++)
            {
                t.RowStyles.Add(i == 8 ? new RowStyle(SizeType.Percent, 100) : new RowStyle(SizeType.AutoSize));
            }
            Controls.Add(t);
        }

        static void AddRow(TableLayoutPanel t, int row, string label, TextBox box, Control extra)
        {
            Label l = new Label();
            l.Text = label;
            l.AutoSize = true;
            l.Anchor = AnchorStyles.Left;
            t.Controls.Add(l, 0, row);
            box.Dock = DockStyle.Fill;
            t.Controls.Add(box, 1, row);
            if (extra != null) t.Controls.Add(extra, 2, row);
            else t.SetColumnSpan(box, 2);
        }

        void SetRunning(bool running)
        {
            txtKunde.Enabled = txtTechniker.Enabled = txtOrdner.Enabled = !running;
            btnBrowse.Enabled = chkStore.Enabled = chkKey.Enabled = btnStart.Enabled = !running;
            progress.Visible = running;
            UseWaitCursor = running;
        }

        void Log(string line)
        {
            if (line == null) return;
            if (InvokeRequired) { BeginInvoke((MethodInvoker)delegate { Log(line); }); return; }
            txtLog.AppendText(line + Environment.NewLine);
        }

        // -------------------------------------------------------------------
        // Ablauf
        // -------------------------------------------------------------------

        void OnBrowse(object sender, EventArgs e)
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "Ordner für den Report wählen";
                if (Directory.Exists(txtOrdner.Text)) d.SelectedPath = txtOrdner.Text;
                if (d.ShowDialog(this) == DialogResult.OK) txtOrdner.Text = d.SelectedPath;
            }
        }

        void OnStart(object sender, EventArgs e)
        {
            string kunde = Clean(txtKunde.Text);
            string techniker = Clean(txtTechniker.Text);
            string ordner = txtOrdner.Text.Trim();

            if (kunde.Length == 0 &&
                MessageBox.Show(this, "Es ist kein Kunde eingetragen. Trotzdem fortfahren?", Text,
                                MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
            {
                txtKunde.Focus();
                return;
            }
            if (!IsWritable(ordner))
            {
                MessageBox.Show(this, "In diesen Ordner kann nicht geschrieben werden:\n" + ordner, Text,
                                MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            SaveSetting("Techniker", techniker);

            reportPath = Path.Combine(ordner, string.Format(CultureInfo.InvariantCulture,
                "Inventur_{0}_{1:yyyy-MM-dd}.md", Environment.MachineName, DateTime.Now));
            if (File.Exists(reportPath) &&
                MessageBox.Show(this, "Der Report existiert bereits und wird überschrieben:\n" + reportPath, Text,
                                MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
            {
                return;
            }

            try
            {
                tempScript = Path.Combine(Path.GetTempPath(), "win-inventory-" + Guid.NewGuid().ToString("N") + ".ps1");
                using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
                using (FileStream f = File.Create(tempScript))
                {
                    res.CopyTo(f);
                }

                StringBuilder args = new StringBuilder();
                args.Append("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ").Append(Quote(tempScript));
                args.Append(" -OutputPath ").Append(Quote(reportPath));
                if (kunde.Length > 0) args.Append(" -Kunde ").Append(Quote(kunde));
                if (techniker.Length > 0) args.Append(" -Techniker ").Append(Quote(techniker));
                if (!chkStore.Checked) args.Append(" -NoStoreApps");
                if (chkKey.Checked) args.Append(" -IncludeProductKey");

                Encoding oem = ConsoleEncoding();
                ProcessStartInfo psi = new ProcessStartInfo(PowerShellPath(), args.ToString());
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = oem;
                psi.StandardErrorEncoding = oem;

                proc = new Process();
                proc.StartInfo = psi;
                proc.EnableRaisingEvents = true;
                proc.OutputDataReceived += delegate(object s, DataReceivedEventArgs a) { Log(a.Data); };
                proc.ErrorDataReceived += delegate(object s, DataReceivedEventArgs a) { Log(a.Data); };
                proc.Exited += OnExited;

                txtLog.Clear();
                btnOpen.Visible = btnFolder.Visible = false;
                lblStatus.Text = "Inventur läuft, das dauert meist unter einer Minute …";
                SetRunning(true);

                proc.Start();
                proc.BeginOutputReadLine();
                proc.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                SetRunning(false);
                CleanupTemp();
                lblStatus.Text = "Start fehlgeschlagen.";
                Log(ex.Message);
            }
        }

        void OnExited(object sender, EventArgs e)
        {
            Process p = (Process)sender;
            p.WaitForExit();   // wartet, bis alle Ausgaben gelesen sind
            int code = p.ExitCode;
            BeginInvoke((MethodInvoker)delegate
            {
                SetRunning(false);
                CleanupTemp();
                proc = null;
                if (code == 0 && File.Exists(reportPath))
                {
                    lblStatus.Text = "Fertig: " + Path.GetFileName(reportPath);
                    btnOpen.Visible = btnFolder.Visible = true;
                    btnFolder.Focus();
                }
                else
                {
                    lblStatus.Text = "Inventur fehlgeschlagen (Code " + code + "), siehe Protokoll.";
                }
            });
        }

        void OnOpenReport(object sender, EventArgs e)
        {
            try { Process.Start(reportPath); }
            catch (Win32Exception) { Process.Start("notepad.exe", Quote(reportPath)); }
        }

        void OnOpenFolder(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", "/select," + Quote(reportPath));
        }

        void OnWebsite(object sender, LinkLabelLinkClickedEventArgs e)
        {
            // Ueber explorer.exe, damit der Browser nicht mit den Adminrechten
            // dieses Prozesses startet.
            try { Process.Start("explorer.exe", "https://" + Website); }
            catch (Exception) { }
        }

        void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (proc == null) return;
            if (MessageBox.Show(this, "Die Inventur läuft noch. Abbrechen und schließen?", Text,
                                MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
            {
                e.Cancel = true;
                return;
            }
            try { proc.Exited -= OnExited; proc.Kill(); proc.WaitForExit(3000); } catch { }
            CleanupTemp();
        }

        // -------------------------------------------------------------------
        // Hilfen
        // -------------------------------------------------------------------

        static string PowerShellPath()
        {
            // Ein 32-Bit-Prozess auf 64-Bit-Windows wuerde sonst die 32-Bit-PowerShell
            // starten und eine umgeleitete Registry sehen.
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string sys = (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess) ? "Sysnative" : "System32";
            return Path.Combine(win, sys + @"\WindowsPowerShell\v1.0\powershell.exe");
        }

        [DllImport("kernel32.dll")]
        static extern int GetOEMCP();

        static Encoding ConsoleEncoding()
        {
            // PowerShell schreibt in die unsichtbare Konsole mit der OEM-Codepage des
            // Systems. CultureInfo.TextInfo.OEMCodePage taugt dafuer nicht: Regionsformate
            // ohne eigene Codepage (z. B. de-IT, en-DE, en-AT) liefern dort nur 1.
            try { return Encoding.GetEncoding(GetOEMCP()); }
            catch (Exception) { return Encoding.Default; }
        }

        static string DefaultFolder()
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            if (IsWritable(exeDir)) return exeDir;
            return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        }

        static bool IsWritable(string dir)
        {
            try
            {
                if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
                string probe = Path.Combine(dir, ".inventur-" + Guid.NewGuid().ToString("N"));
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return true;
            }
            catch { return false; }
        }

        static string Clean(string s)
        {
            // Anfuehrungszeichen wuerden die Kommandozeile brechen
            return (s ?? "").Replace("\"", "").Trim();
        }

        static string Quote(string s)
        {
            return "\"" + s + "\"";
        }

        void CleanupTemp()
        {
            if (tempScript == null) return;
            try { File.Delete(tempScript); } catch { }
            tempScript = null;
        }

        static string LoadSetting(string name)
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKey))
                {
                    object v = k == null ? null : k.GetValue(name);
                    return v == null ? "" : v.ToString();
                }
            }
            catch { return ""; }
        }

        static void SaveSetting(string name, string value)
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(SettingsKey))
                {
                    k.SetValue(name, value);
                }
            }
            catch { }
        }
    }
}
