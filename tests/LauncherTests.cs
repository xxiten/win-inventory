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
using Microsoft.Win32;

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
            TestStartInfo(work);
            TestQuote();
            TestFolders();
            TestUpdateCheck();

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            TestIcons();

            bool admin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            if (admin) WithSavedTechniker(delegate { TestInventoryRun(work); });
            else Console.WriteLine("--      Inventurlauf ueber die Exe uebersprungen (keine Adminrechte)");

            return failures;
        }

        // BuildStartInfo: Werte muessen unveraendert bei PowerShell 5.1 ankommen, Schalter nur
        // wenn gewuenscht, und der Exit-Code muss Erfolg und Abbruch unterscheiden.
        static void TestStartInfo(string work)
        {
            string echo = Path.Combine(work, "echo.ps1");
            string outFile = Path.Combine(work, "echo-out.txt");
            File.WriteAllText(echo,
                "param($OutputPath, $Kunde, $Station, $Techniker, [switch]$NoStoreApps, [switch]$IncludeProductKey)\r\n" +
                "$ErrorActionPreference = 'Stop'\r\n" +
                "[IO.File]::WriteAllText('" + outFile + "', ($Kunde, $Station, $Techniker, $OutputPath, " +
                "[string]$NoStoreApps, [string]$IncludeProductKey -join \"`n\"), [Text.Encoding]::UTF8)\r\n" +
                "Write-Error 'nicht kritisch' -ErrorAction Continue\r\n" +
                "if ($Kunde -eq 'ABBRUCH') { throw 'Abbruch' }\r\n",
                new UTF8Encoding(true));
            string[][] cases = {
                new[] { "Muster\\", "Max", "" },
                new[] { "\"Zur Post\" GmbH", "NETIXX\\moberleiter", "x y\\\\" },
                new[] { "-IncludeProductKey", "-S", "-Verbose" },
                new[] { "M\u00fcller & S\u00f6hne $(calc) `n", "\u00dcnal ' ; -IncludeProductKey", "a\\\"b" },
            };
            int i = 0;
            foreach (string[] c in cases)
            {
                i++;
                bool switches = i == 2;
                ProcessStartInfo psi = (ProcessStartInfo)Call("BuildStartInfo", echo, @"C:\Temp\x.md", c[0], c[1], c[2], switches, switches);
                psi.CreateNoWindow = true;
                psi.RedirectStandardError = true;   // das absichtliche Write-Error nicht ins Testprotokoll
                if (File.Exists(outFile)) File.Delete(outFile);
                int code;
                using (Process p = Process.Start(psi)) { p.StandardError.ReadToEnd(); p.WaitForExit(); code = p.ExitCode; }
                string[] got = File.Exists(outFile) ? File.ReadAllText(outFile, Encoding.UTF8).Split('\n') : new string[6];
                Check("Start Fall " + i + " Kunde", c[0], got[0]);
                Check("Start Fall " + i + " Station", c[1], got[1]);
                Check("Start Fall " + i + " Techniker", c[2], got[2]);
                Check("Start Fall " + i + " OutputPath", @"C:\Temp\x.md", got[3]);
                Check("Start Fall " + i + " Schalter", switches + "/" + switches, got[4] + "/" + got[5]);
                Check("Start Fall " + i + " Exit-Code 0", "0", code.ToString());
            }
            ProcessStartInfo fail = (ProcessStartInfo)Call("BuildStartInfo", echo, @"C:\Temp\x.md", "ABBRUCH", "", "", false, false);
            fail.CreateNoWindow = true;
            fail.RedirectStandardError = true;
            using (Process p = Process.Start(fail)) { p.StandardError.ReadToEnd(); p.WaitForExit(); Check("Abbruch des Skripts ergibt Exit-Code 1", "1", p.ExitCode.ToString()); }
        }

        // Quote dient nur noch fuer Pfade an explorer.exe
        static void TestQuote()
        {
            Check("Quote Pfad", "\"C:\\Temp\\x.md\"", (string)Call("Quote", @"C:\Temp\x.md"));
            Check("Quote Backslash am Ende", "\"E:\\\\\"", (string)Call("Quote", @"E:\"));
        }

        static void TestFolders()
        {
            Check("NormalizeFolder E:", @"E:\", (string)Call("NormalizeFolder", "E:"));
            Check("NormalizeFolder mit Leerzeichen", @"C:\Temp\", (string)Call("NormalizeFolder", @"  C:\Temp\  "));
            Check("NormalizeFolder mit Anfuehrungszeichen", @"C:\Temp", (string)Call("NormalizeFolder", "\"C:\\Temp\""));
            Check("Exe-Ordner im Laufwerksstamm", @"E:\", Path.GetDirectoryName(@"E:\Inventur.exe"));
        }

        // Versionspruefung ohne Netz: Antwort der GitHub-API auswerten und vergleichen
        static void TestUpdateCheck()
        {
            Check("Tag aus API-Antwort", "v0.9.1",
                  (string)Call("ParseLatestTag", "{\"url\":\"x\",\"tag_name\": \"v0.9.1\",\"name\":\"v0.9.1\"}"));
            Check("Tag mit Zusatz wird verworfen", null, (string)Call("ParseLatestTag", "{\"tag_name\":\"v1.0.0-rc1\"}"));
            Check("Tag mit fremden Zeichen wird verworfen", null, (string)Call("ParseLatestTag", "{\"tag_name\":\"v1.0.0\\\" & calc\"}"));
            Check("Leere Antwort", null, (string)Call("ParseLatestTag", (object)null));
            Version current = new Version(0, 9, 0, 0);
            Check("0.9.1 ist neuer als 0.9.0", "True", Call("IsNewer", "v0.9.1", current).ToString());
            Check("1.0.0 ist neuer als 0.9.0", "True", Call("IsNewer", "v1.0.0", current).ToString());
            Check("0.9.0 ist nicht neuer als 0.9.0", "False", Call("IsNewer", "v0.9.0", current).ToString());
            Check("0.8.4 ist nicht neuer als 0.9.0", "False", Call("IsNewer", "v0.8.4", current).ToString());
            Check("0.10.0 ist neuer als 0.9.0", "True", Call("IsNewer", "v0.10.0", current).ToString());
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
            ((TextBox)Field(f, "txtStation")).Text = "-Empfang \"1\"";
            ((TextBox)Field(f, "txtTechniker")).Text = "LauncherTests";
            ((TextBox)Field(f, "txtOrdner")).Text = target;
            ((CheckBox)Field(f, "chkStore")).Checked = false;

            string tempDir = null;
            bool tempProtected = false;
            string tempOwner = null;
            string status = "", log = "";
            DateTime start = DateTime.Now;
            Timer poll = new Timer();
            poll.Interval = 500;
            poll.Tick += delegate
            {
                if (tempDir == null && Field(f, "tempDir") != null)
                {
                    tempDir = (string)Field(f, "tempDir");
                    DirectorySecurity ds = Directory.GetAccessControl(tempDir);
                    tempProtected = ds.AreAccessRulesProtected;
                    tempOwner = ds.GetOwner(typeof(SecurityIdentifier)).Value;
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
            Check("Temp-Ordner gehoert den Administratoren", "S-1-5-32-544", tempOwner);
            Check("Temp-Ordner danach entfernt", "False", (tempDir != null && Directory.Exists(tempDir)).ToString());
            Check("Report geschrieben", "True", File.Exists(report).ToString());
            if (File.Exists(report))
            {
                string first = File.ReadAllLines(report, Encoding.UTF8)[0];
                Check("Report-Ueberschrift mit Station", "# Inventur -Empfang \"1\" (" + Environment.MachineName + ")", first);
            }
            f.Dispose();
        }

        // OnStart merkt sich den Techniker in HKCU. Der Test darf den echten Wert nicht ersetzen.
        static void WithSavedTechniker(Action test)
        {
            string key = (string)typeof(MainForm).GetField("SettingsKey", Any).GetValue(null);
            object original;
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(key)) original = k == null ? null : k.GetValue("Techniker");
            try { test(); }
            finally
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(key))
                {
                    if (original != null) k.SetValue("Techniker", original);
                    else k.DeleteValue("Techniker", false);
                }
            }
        }
    }
}
