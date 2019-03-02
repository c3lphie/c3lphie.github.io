---
layout: post
title:  "Den Digitale Prøvevagt situation"
date:   2019-03-01 11:47:34 +0100
categories: Write-ups
---
## Indledning
Som mange nok ved, har Undervisningsministeriet besluttet, at der skal fokuseres mere på snyd, og forebyggelse af dette. Derfor har Undervisningsministeriet udviklet et program der overvåger eksaminandens pc under hele eksamensperioden. Dette program hentes, installeres og køres inden eksamensstart. Undervisningsministeriet har gjort det til et krav at bruge dette software ved navnet "Den Digitale Prøvevagt", forkortet til "DDP".
Programmet virker, i skrivende stund, kun til Windows og MacOS. Har man et andet styresystem en de to f.eks. en Linux distribution får eleven enten en låne bærbar tildelt, eller så tager de prøven med skærpet tilsyn. Når prøven slutter vil programmet stoppe. Herefter kan eleven vælge og afinstallere DDP, eller lade være hvis der er flere skriftlige prøver han/hun skal til.
Nægter man at hente, installere og køre DDP under eksamenstiden så kan man ikke gå op til eksamen og derved dumper man.

> Det er et krav, at alle gymnasiale institutioner benytter ministeriets digitale prøveafviklingssystem ved de centralt stillede, skriftlige prøver. Det vil fra og med sommertermin 2019, med enkelte undtagelser, være en forudsætning for at deltage i de skriftlige prøver i de gymnasiale uddannelser, at eleven installerer og afvikler monitoreringsprogrammet på sin computer under skriftlige prøver.

(Kilde: [Undervisningsministeriets side om prøvevagten][uvm-info])

Som så mange andre gymnasie elever, synes jeg det er en meget forkert tilgang. At vi skal installere et stykke software der i bund og grund er spyware, for at vi kan komme op til en skriftlig eksamen. Ifølge en debat på facebook([link][fb-debat]), er der flere ting som virker skummelt ved programmet. Jeg har derfor, i samarbejde med en af mine venner, forsøgt at komme tilbunds i hvad dette program helt præcist gør.

## Metode
<u>Vi kiggede kun på Windows versionen af programmet</u>

For at finde ud af hvordan programmet fungerer skal vi først finde ud af hvordan programmet er bygget. Vi kan heldigvis hurtigt finde ud af hvordan programmet er lavet ved at kigge på de filer der ligger i den mappe hvori DDP ligger. Heri kan vi finde filer som tyder på at programmet er skrevet i C# med Microsofts ".NET Framework". Det er perfekt da programmer der er skrevet i C# indeholder meget af den oprindelige kildekode. Det betyder at vi kan anvende et decompilation program som dnSpy til at se programmets kildekode. Det er samme metode som [Alexander Norup][alex-norup] brugte.

## Fund
I brugervejledningen til den prøvevagts ansvarlige står der hvilke data som de kan tilgå fra DDP.
- Skærmbilleder
- Processer der køre på computeren
- Besøgte hjemmesider
- Netværkskonfiguration
- Om programmet bliver kørt i en virtuel maskine

I kildekoden gjorde vi flere interessante fund, der iblandt det som der står i brugervejledningen, men også nogle lidt mere skumle ting. Som kan ses nedenfor:
- Keylogger
- Udklipslogger
- Skærmbillede
- Netværkstrafik
- Netværkskonfiguration
- Browser type
- Kørende programmer på maskinen
- Virtuel maskine detektion
- Maskine fingeraftryk
- Server(Som bliver brugt at Undervisningsministeriet)

DDP fungere ved af såkaldte "workers", der er en til hver af de indbyggede funktioner programmet har. De sender den data de indsamler til en "CommunicationManager", som sender det videre til en server.

# Keylogger
I det oplæg omkring DDP vi fik på fik vi ingenting at om der var en keylogger i programmet. Havde læst om at der var en på Alexander Norups [blog][alex-norup], var lidt skeptisk hvilket også var en af motivationerne til at tjekke efter selv.
Keyloggeren består af to klasser, `KeyloggerHelper.cs` og `KeyloggerWorker.cs`. `KeyloggerHelper.cs` er det bibliotek som de har skrevet for at kunne indsamle tastetryk.`KeyloggerWorker.cs`står for at udføre selve indsamlingen og sende det til "CommunicationManager".

Den mest interessante af de to klasser er `KeyloggerWorker.cs`, fordi det er den der gør det meste af arbejdet hvor `KeyloggerHelper.cs` bare er et bibliotek for at gøre tingene nemmere.

```cs
private StringBuilder _builder = new StringBuilder();
...
private void KeyloggerHelper_KeyPressed(object sender, KeyEventArgs e)
{
  if (!char.IsLetterOrDigit((char) e.KeyCode))
    this._builder.Append("[" + (object) e.KeyCode + "]");
  else
    this._builder.Append((object) e.KeyCode);
}
```
Den ovenstående kode sætter elevens tastetryk ind i `_builder`, som er et `StringBuilder` objekt. Hvilket vil sige at den bygger en streng af tekst, som det lyder af navnet. Og det er ALLE tastetryk! Det første den gør det er at tjekke om tasten er et bogstav eller et tal. Er det ikke tilfældet, f.eks. hvis der bliver trykket på mellemrums tasten, så vil den tage tastekoden og formegentlig logge det som `[SPACE]` i logfilen.

# Udklipslogger
At den kunne se hvad der ligger i udklipholderen var ikke overraskelse da det var en af de ting vi blev informeret om under oplægget.
```cs
protected override List<DataPackage> GetDataPackages()
{
  return new List<DataPackage>()
  {
    new DataPackage(DataPackage.ColTypeEnum.Clipb, new bool?(false), !Clipboard.ContainsText() ? Encoding.UTF8.GetBytes("no text") : Encoding.UTF8.GetBytes(Clipboard.GetText()), new DateTime?(DataPackageEnvelopeAwsReceiver.ServerTime), new long?((long) this.GetAndIncrementWorkSequence()))
  };
}
```
Det som den gør er simplere en det umiddelbart ser ud. Den tjekker om der er noget i udklipsholderen, er der ikke det logger den "no text". Hvis der er noget i udklipsholderen, gemmer den det i logfilen.

# Skærmbillede
På samme måde som der var to klasser ved keyloggeren er der også to klasser i spil ved skærmbillede funktionen. `ScreenCaptureTool.cs` og `ScreenshotWorker.cs` hvor workeren var den mest interessante ved keyloggeren, så er det her `ScreenCaptureTool.cs` der er mest interessant.

```cs
public static Image CaptureScreenNew()
{
  try
  {
    Rectangle bounds = Screen.PrimaryScreen.Bounds;
    Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height);
    Size blockRegionSize = new Size(bitmap.Width, bitmap.Height);
    using (Graphics graphics = Graphics.FromImage((Image) bitmap))
    {
      graphics.CopyFromScreen(0, 0, 0, 0, blockRegionSize);
      return (Image) bitmap;
    }
  }
  catch (Exception ex)
  {
    StaticFileLogger.Current.LogEvent("ScreenCaptureTool.CaptureScreenNew()", "Exception taking screenshot", string.Format("Error is: '{0}'", (object) ex.ToString()), EventLogEntryType.Information);
    return ScreenCaptureTool.WriteExceptionToImage(ex);
  }
}
```
Funktionen `CaptureScreenNew` forsøger først at lave et bitmap billede af hele skærmen. Hvis dette ikke lykkes har de skrevet funktionen `WriteExceptionToImage`, der vises her:
```cs
private static Image WriteExceptionToImage(Exception ex)
{
  Bitmap bitmap = new Bitmap(800, 600);
  Size size = bitmap.Size;
  size.Height -= 20;
  size.Width -= 20;
  RectangleF layoutRectangle = new RectangleF(new PointF(10f, 10f), (SizeF) size);
  using (Graphics graphics = Graphics.FromImage((Image) bitmap))
  {
    GraphicsUnit pageUnit = GraphicsUnit.Pixel;
    graphics.FillRectangle(Brushes.Wheat, bitmap.GetBounds(ref pageUnit));
    graphics.SmoothingMode = SmoothingMode.AntiAlias;
    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
    graphics.DrawString(ex.ToString(), new Font("Tahoma", 10f), Brushes.Black, layoutRectangle);
  }
  return (Image) bitmap;
}
```
`WriteExceptionToImage` Skaber et billede der viser fejl-beskeden som et billede, dette er bare fejlsikring. Grunden til at de har valgt at gøre det sådan er i tilfældet af bugs. Dette gør at teknikere har informationer de kan arbejde ud fra, uden at skulle tænke på evt. data der kunne være på screenshots.

```cs
private static ImageCodecInfo GetEncoder(ImageFormat format)
{
  foreach (ImageCodecInfo imageDecoder in ImageCodecInfo.GetImageDecoders())
  {
    if (imageDecoder.FormatID == format.Guid)
      return imageDecoder;
  }
  return (ImageCodecInfo) null;
}
```
`GetEncoder` laver bitmap værdierne om til et hvilket som helst billedtype.

```cs
public static byte[] ImageToByteArray(Image imageIn, int jpgCompressionLevel = 30)
{
  MemoryStream memoryStream = new MemoryStream();
  EncoderParameters encoderParams = new EncoderParameters(1);
  encoderParams.Param[0] = new EncoderParameter(Encoder.Quality, (long) jpgCompressionLevel);
  imageIn.Save((Stream) memoryStream, ScreenCaptureTool.GetEncoder(ImageFormat.Jpeg), encoderParams);
  return memoryStream.ToArray();
}
```
`ImageToByteArray` tager imod to argumenter, et billede og et kompressionsniveau for jpg billedet. Den vigtigste del af denne funktion er `imageIn.Save((Stream) memoryStream, ScreenCaptureTool.GetEncoder(ImageFormat.Jpeg), encoderParams);`. Det der sker her er at billedet bliver konverteret til jpg format, derefter logget som en masse hexværdier.

# Netværkstrafik
DDP har også funktionen til at se hvilke sider man tilgår når man søger på nettet. Programmet kan derved advare den eksamens ansvarlige og sige at nu går eleven på facebook, netflix eller andre ikke tilladte sider.

Her til har de skabt en worker, der læser og gemmer den url som der bliver brugt af browseren.
```cs
protected override List<DataPackage> GetDataPackages()
{
  CurrentBrowserUrlsTool.GetHarvestedUrlsFromRunningProcessesAndEmptyTheList().ToList<string>().ForEach((Action<string>) (url => this._urls.Add(url)));
  List<string> list = this._urls.ToList<string>();
  list.Sort();
  byte[] bytes = Encoding.UTF8.GetBytes(string.Join(";", (IEnumerable<string>) list));
  this._urls.Clear();
  return new List<DataPackage>()
  {
    new DataPackage(DataPackage.ColTypeEnum.Sites, new bool?(false), bytes, new DateTime?(DataPackageEnvelopeAwsReceiver.ServerTime), new long?((long) this.GetAndIncrementWorkSequence()))
  };
}
```
### Browser type
For at de kan læse url'en i en browser skal de først vide hvilken browser der er tale om. Har de skrevet klasse der håndterer alt det der har med browsere at gøre. Den nedenstående funktion bliver brugt til at tjekke om navnene på de processer der kører i baggrunden er en browser. 
```cs
private static CurrentBrowserUrlsTool.BrowserType Parse(string processName)
{
  processName = processName.ToLower();
  if (processName.Contains("chrome"))
    return CurrentBrowserUrlsTool.BrowserType.GOOGLE_CHROME;
  if (processName.Contains("applicationframehost"))
    return CurrentBrowserUrlsTool.BrowserType.MICROSOFT_EDGE;
  if (processName.Contains("iexplore"))
    return CurrentBrowserUrlsTool.BrowserType.INTERNET_EXPLORER;
  return processName.Contains("firefox") ? CurrentBrowserUrlsTool.BrowserType.FIREFOX : CurrentBrowserUrlsTool.BrowserType.Empty;
}
```
Dette betyder at for windows versionen af DDP, tjekker de kun efter om det enten er Google Chrome, Firefox, Microsoft Edge eller Internet Explorer. De kan i denne version af DDP ikke gøre noget hvis du bruger Opera som browser.

I denne klasse har de også lavet en funktion der trækker url'en ud af en browser. Dette er en længere funktion ved navnet `GetURLFromProcess`, derfor går jeg hurtigt over den. Men det som den gør som noget af det første er at finde ud af om der overhovedet er en af de kendte browserer åben. Er dette tilfældet bruger den forskellige metoder til at skaffe url'en alt efter browseren.

# Netværkskonfiguration
Ifølge den førnævnte bruger vejledning så bliver netværkskonfigurationen ikke vist i den nuværende version. Det bliver ikke brugt til at skabe fingeraftrykket af maskinen, men det bliver med højsandsynligt brugt til at tjekke om der er forbindelse til en VPN eller Proxy. En VPN kunne i et eksamens tilfælde bruges til at lave en forbindelse hjem hvor et familie medlem kunne lave opgaven for eleven.

```cs
private StringBuilder _builder = new StringBuilder();
private int _numberOfInterfacesAtLastCount;
...
internal string GetNetworkConfigurationData()
{
  this._builder.Clear();
  NetworkInterface[] allNetworkInterfaces = NetworkInterface.GetAllNetworkInterfaces();
  this._numberOfInterfacesAtLastCount = allNetworkInterfaces.Count<NetworkInterface>();
  (from nwi in allNetworkInterfaces.ToList<NetworkInterface>()
  orderby nwi.OperationalStatus
  select nwi).ToList<NetworkInterface>().ForEach(delegate(NetworkInterface nwi)
  {
    this._builder.Append(nwi.GetStateAsString());
  });
  return this._builder.ToString();
}
```
Det ovenstående uddrag af kildekoden sætter alle netværkskonfigurationerne ind i `_builder` på samme måde som keyloggeren indsatte taste tryk i dens `_builder`. Herefter logger den informationerne til logfilen.

# Kørende programmer på maskinen
```cs
private int _lastNumberOfRunningProcesses = 0;
...
protected override List<DataPackage> GetDataPackages()
{
  Process[] processes = Process.GetProcesses();
  this._lastNumberOfRunningProcesses = ((IEnumerable<Process>) processes).Count<Process>();
  string s = "";
  foreach (Process process in processes)
  {
    s = s + "Id=" + (object) process.Id + ",Name =" + process.ProcessName + ",";
    try
    {
      s = s + "Description=" + process.MainModule.FileVersionInfo.FileDescription + ";";
    }
    catch (Exception ex)
    {
      if (ex.ToString() != "")
        s += "Description=;";
    }
  }
  return new List<DataPackage>()
  {
    new DataPackage(DataPackage.ColTypeEnum.Plist, new bool?(false), Encoding.UTF8.GetBytes(s), new DateTime?(DataPackageEnvelopeAwsReceiver.ServerTime), new long?((long) this.GetAndIncrementWorkSequence()))
  };
}
```

# Virtuel maskine detektion
Programmet tjekker om det kører i en virtuel maskine. En virtuel maskine er et stykke software der emulere en computer. Det vil sige at du kan f.eks. kan køre Windows 10 inde i Windows 10. Denne beskyttelse er taget i brug fordi at en elev kan snyde hvis at eleven laver opgaven og kører DDP i den virtuelle maskine. Så kan DDP ikke overvåge elevens egentlige system, men kun den virtuelle maskine.
```cs
public bool AmIRunningInsideAVirtualMachine()
{
  bool flag = false;
  try
  {
    foreach (ManagementBaseObject managementBaseObject in new ManagementObjectSearcher("root\\CIMV2", "SELECT * FROM Win32_BaseBoard").Get())
      flag = managementBaseObject["Manufacturer"].ToString().ToLower() == "microsoft corporation".ToLower();
    return flag;
  }
  catch
  {
    return flag;
  }
}
```
Her tjekker programmet om det kører i en virtuel maskine ved at tjekke bundkortets fabrikant. Hvis det er Microsoft Corporation er der stor chance for at programmet kører i en virtuel maskine.

Programmet tjekker også om at der kører en virtual maskine på computeren. Det gør den ved at den har en liste af processer der er kendte virtuel maskiner og tjekker dem på en liste af nuværende kørende processer.
```cs
private static readonly List<string> _vmSubStrings = new List<string>
  {
    "vmware",
    "virtualpc",
    "virtualbox"
  };
```
Her er listen af kendte virtuel maskine processere.

```cs
private bool IsVirtualMachineProcessRunning()
  {
    Process[] processes = Process.GetProcesses();
    return processes.Any((Process p) => 
      p.ProcessName.ContainsOneOrMoreInList(VirtualMachineDetectionWorker._vmSubStrings));
  }
```
Her tjekker den om en virtuel maskine kører ved at se om nogle af de processer der kører på computeren matcher en af de kendte virtuel maskine processer.


# Maskine fingeraftryk
DDP laver et fingeraftryk af din maskine, som den kan bruge til at identificere din maskine. Den laver denne identifikation baseret på det hardware der er i din maskine, så den vil også kunne vide at det er dig selvom at du har geninstalleret Windows.

## DPV.exe.config

# Server

## Regler og love

## Diskussion

## Konklusion


[uvm-info]: https://uvm.dk/gymnasiale-uddannelser/proever-og-eksamen/netproever/den-digitale-proevevagt/om-den-digitale-proevevagt
[fb-debat]: https://www.facebook.com/jeanette.feldballe/posts/10214797289978061
[alex-norup]: https://www.alexandernorup.com/DigitalProvevagt?fbclid=IwAR2Hp_fDZHZh4FALcVJCnciM-w3z1kMafh_bilPboIlLpeylNJhdKIvYCYY
