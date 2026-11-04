// Tests fuer src/InventurLauncher.cs, aufgerufen von tests/Invoke-Tests.ps1.
// Ruft die internen Hilfsfunktionen per Reflection auf. Mit Adminrechten (z. B. im
// GitHub-Runner) laeuft zusaetzlich eine komplette Inventur ueber das Fenster.
// Ausgaben nur in ASCII, damit sie in jedem Konsolen-Log lesbar bleiben.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace WinInventory
{
    static class LauncherTests
    {
        static int failures;
        const BindingFlags Any = BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance;

        static void Check(string name, string expected, string actual)
        {
            if (expected == actual) { Console.WriteLine("OK      " + name); return; }
            failures++;
            Console.WriteLine("FEHLER  " + name);
            Console.WriteLine("        erwartet: [" + Ascii(expected) + "]");
            Console.WriteLine("        bekommen: [" + Ascii(actual) + "]");
        }

        static string Ascii(string s)
        {
            if (s == null) return "(null)";
            StringBuilder sb = new StringBuilder();
            foreach (char c in s) sb.Append(c < 128 ? c.ToString() : "\\u" + ((int)c).ToString("x4"));
            return sb.ToString();
        }

        static object Call(string method, params object[] args)
        {
            return typeof(MainForm).GetMethod(method, Any).Invoke(null, args);
        }

        static object Field(object form, string name)
        {
            return typeof(MainForm).GetField(name, Any).GetValue(form);
        }

        [STAThread]
        static int Main(string[] args)
        {
            string work = args[0];
            TestQuote(work);
            TestFolders();

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            TestIcons();

            bool admin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            if (admin) TestInventoryRun(work);
            else Console.WriteLine("--      Inventurlauf ueber die Exe uebersprungen (keine Adminrechte)");

            return failures;
        }

        // Werte muessen unveraendert bei PowerShell 5.1 (-File) ankommen.
        static void TestQuote(string work)
        {
            string echo = Path.Combine(work, "echo.ps1");
            string outFile = Path.Combine(work, "echo-out.txt");
            File.WriteAllText(echo,
                "param($OutputPath, $Kunde, $Station, [switch]$IncludeProductKey)\r\n" +
                "[IO.File]::WriteAllText('" + outFile + "', ($Kunde, $Station, $OutputPath, [string]$IncludeProductKey -join \"`n\"), [Text.Encoding]::UTF8)\r\n",
                new UTF8Encoding(true));
            string[][] cases = {
                new[] { "Muster\\", "Max" },
                new[] { "\"Zur Post\" GmbH", "NETIXX\\moberleiter" },
                new[] { "a\\\"b", "x y\\\\" },
                new[] { "M\u00fcller & S\u00f6hne $(calc) `n", "\u00dcnal ' ; -IncludeProductKey" },
            };
            int i = 0;
            foreach (string[] c in cases)
            {
                i++;
                string a = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Call("Quote", echo) +
                           " -OutputPath " + Call("Quote", @"C:\Temp\x.md") +
                           " -Kunde " + Call("Quote", c[0]) + " -Station " + Call("Quote", c[1]);
                if (File.Exists(outFile)) File.Delete(outFile);
                ProcessStartInfo psi = new ProcessStartInfo(
                    Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"), a);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                using (Process p = Process.Start(psi)) p.WaitForExit();
                string[] got = File.Exists(outFile) ? File.ReadAllText(outFile, Encoding.UTF8).Split('\n') : new string[4];
                Check("Quote Fall " + i + " erster Wert", c[0], got[0]);
                Check("Quote Fall " + i + " zweiter Wert", c[1], got[1]);
                Check("Quote Fall " + i + " OutputPath", @"C:\Temp\x.md", got[2]);
                Check("Quote Fall " + i + " kein Schalter eingeschleust", "False", got[3]);
            }
        }

        static void TestFolders()
        {
            Check("NormalizeFolder E:", @"E:\", (string)Call("NormalizeFolder", "E:"));
            Check("NormalizeFolder mit Leerzeichen", @"C:\Temp\", (string)Call("NormalizeFolder", @"  C:\Temp\  "));
            Check("Exe-Ordner im Laufwerksstamm", @"E:\", Path.GetDirectoryName(@"E:\Inventur.exe"));
        }

        static void TestIcons()
        {
            using (MainForm f = new MainForm())
            {
                Check("Kleines Icon aus der Exe geladen", "True", ((IntPtr)Field(f, "smallIcon") != IntPtr.Zero).ToString());
                Check("Grosses Icon in Systemgroesse", SystemInformation.IconSize.Width.ToString(), f.Icon.Width.ToString());
            }
        }

        // Kompletter Lauf ueber das Fenster, wie ein Klick auf "Inventur starten".
        static void TestInventoryRun(string work)
        {
            string target = Path.Combine(work, "report");
            Directory.CreateDirectory(target);
            MainForm f = new MainForm();
            ((TextBox)Field(f, "txtKunde")).Text = "CI-Test & Co";
            ((TextBox)Field(f, "txtStation")).Text = "Empfang \"1\"";
            ((TextBox)Field(f, "txtTechniker")).Text = "LauncherTests";
            ((TextBox)Field(f, "txtOrdner")).Text = target;
            ((CheckBox)Field(f, "chkStore")).Checked = false;

            string tempDir = null;
            bool tempProtected = false;
            string status = "", log = "";
            DateTime start = DateTime.Now;
            Timer poll = new Timer();
            poll.Interval = 500;
            poll.Tick += delegate
            {
                if (tempDir == null && Field(f, "tempDir") != null)
                {
                    tempDir = (string)Field(f, "tempDir");
                    tempProtected = Directory.GetAccessControl(tempDir).AreAccessRulesProtected;
                }
                bool running = Field(f, "proc") != null;
                if (running && (DateTime.Now - start).TotalMinutes < 8) return;
                poll.Stop();
                if (running)
                {
                    failures++;
                    Console.WriteLine("FEHLER  Inventurlauf nach 8 Minuten nicht fertig");
                    try { ((Process)Field(f, "proc")).Kill(); } catch { }
                    typeof(MainForm).GetField("proc", Any).SetValue(f, null);
                }
                // Vor dem Schliessen lesen: nach dem Zerstoeren der Fenster ist der Protokolltext weg
                status = ((Label)Field(f, "lblStatus")).Text;
                log = ((TextBox)Field(f, "txtLog")).Text;
                f.Close();
            };
            f.Shown += delegate
            {
                typeof(MainForm).GetMethod("OnStart", Any).Invoke(f, new object[] { null, EventArgs.Empty });
                poll.Start();
            };
            f.ShowInTaskbar = false;
            f.WindowState = FormWindowState.Minimized;
            Application.Run(f);

            string report = (string)Field(f, "reportPath");
            Check("Inventurlauf Status \"" + Ascii(status) + "\"", "True", status.StartsWith("Fertig").ToString());
            if (!status.StartsWith("Fertig"))
            {
                Console.WriteLine("        Protokoll:");
                foreach (string line in log.Split('\n')) Console.WriteLine("        | " + Ascii(line.TrimEnd('\r')));
            }
            Check("Temp-Ordner unter Windows\\Temp", "True", tempDir != null &&
                  tempDir.StartsWith(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Temp"), StringComparison.OrdinalIgnoreCase) ? "True" : "False");
            Check("Temp-Ordner mit geschuetzten Rechten", "True", tempProtected.ToString());
            Check("Temp-Ordner danach entfernt", "False", (tempDir != null && Directory.Exists(tempDir)).ToString());
            Check("Report geschrieben", "True", File.Exists(report).ToString());
            if (File.Exists(report))
            {
                string first = File.ReadAllLines(report, Encoding.UTF8)[0];
                Check("Report-Ueberschrift mit Station", "# Inventur Empfang \"1\" (" + Environment.MachineName + ")", first);
            }
            f.Dispose();
        }
    }
}
