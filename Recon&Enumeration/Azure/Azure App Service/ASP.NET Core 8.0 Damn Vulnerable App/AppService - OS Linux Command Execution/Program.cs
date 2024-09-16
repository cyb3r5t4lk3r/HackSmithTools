var builder = WebApplication.CreateBuilder(args);

// Přidání Razor Pages do služeb
builder.Services.AddRazorPages();

var app = builder.Build();

// Umožní servírování statických souborů
app.UseStaticFiles();

// Nastavení routingu
app.UseRouting();

// Mapování Razor Pages
app.MapRazorPages();

// Spuštění aplikace
app.Run();
