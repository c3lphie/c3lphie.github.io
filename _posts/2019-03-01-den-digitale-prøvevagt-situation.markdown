---
layout: post
title:  "Den Digitale Prøvevagt situation"
date:   2019-03-04 22:44:34 +0100
categories: Write-ups
---
##### Skrevet af Mads Beyer Mogensen og Simon Søndergaard Christensen

##### Mail: mail@madsmogensen.dk og simon_sc@live.dk

## Indledning
Undervisningsministeriet har besluttet, at der skal fokuseres mere på forebyggelse af snyd under eksamen. Derfor har Undervisningsministeriet udviklet et program, der overvåger eksaminandens PC under hele eksamensperioden. Dette program skal hentes, installeres og køres inden eksamensstart. Dette software er givet navnet "Den Digitale Prøvevagt", forkortet til "DDP".
Programmet virker, kun til Windows og MacOS. Har man et andet styresystem, skal eksaminanden tage kontakt til den eksamensansvarlige for vejledning. Når eksamen er ovre stopper programmet.
Nægter man at hente, installere og køre DDP under eksamenstiden, kan man ikke gå op til eksamen og derved dumper man.

> Det er et krav, at alle gymnasiale institutioner benytter ministeriets digitale prøveafviklingssystem ved de centralt stillede, skriftlige prøver. Det vil fra og med sommertermin 2019, med enkelte undtagelser, være en forudsætning for at deltage i de skriftlige prøver i de gymnasiale uddannelser, at eleven installerer og afvikler monitoreringsprogrammet på sin computer under skriftlige prøver.

(Kilde: [Undervisningsministeriets side om prøvevagten][uvm-info])

Som så mange andre gymnasie elever, synes vi det er en meget forkert tilgang. At vi skal installere et stykke software der i bund og grund er spyware, for at vi kan komme op til en skriftlig eksamen. Ifølge en debat på Facebook([link][fb-debat]), er der flere ting som virker skummelt ved programmet. Vi har der forsøgt at komme til bunds i hvad dette program helt præcist gør.

## Metode
<u>Vi kiggede kun på Windows versionen af programmet, der var tilgængelig d. 28/2-2019</u>

For at finde ud af hvordan programmet fungerer skal vi først finde ud af hvordan programmet er bygget. Vi kan heldigvis hurtigt finde ud af hvordan programmet er lavet ved at kigge på de filer der ligger i den mappe hvori DDP ligger. Heri kan vi finde filer som tyder på at programmet er skrevet i C# med Microsofts ".NET Framework". Det er perfekt da programmer der er skrevet i C# indeholder meget af den oprindelige kildekode. Det betyder at vi kan anvende et decompilation værktøj som dnSpy til at se programmets kildekode. Det er samme metode som [Alexander Norup][alex-norup] brugte.

## Fund
I brugervejledningen til den prøvevagts ansvarlige står der hvilke data som de kan tilgå fra DDP.
- Skærmbilleder
- Processer der køre på computeren
- Besøgte hjemmesider
- Netværkskonfiguration
- Om programmet bliver kørt i en virtuel maskine


I kildekoden gjorde vi flere interessante fund, der iblandt det som der står i brugervejledningen, men også nogle lidt mere skumle ting, som kan ses nedenfor:
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
- Fremtidige funktioner

DDP fungerer ved af såkaldte "workers", der er en til hver af de indbyggede funktioner programmet har. De sender den data de indsamler til en "CommunicationManager", som sender det videre til en server.

# Keylogger
I det oplæg omkring DDP vi fik på fik vi ingenting at om der var en keylogger i programmet. Jeg (Simon) havde læst om at der var en på Alexander Norups [blog][alex-norup], var lidt skeptisk hvilket også var en af motivationerne til at tjekke efter selv.
Keyloggeren består af to klasser, `KeyloggerHelper` og `KeyloggerWorker`. `KeyloggerHelper` indeholder kode, som hjælper med indsamling af tastetryk. `KeyloggerWorker` står for at gemme tastetryk og for at sende tastetryk til "CommunicationManager".


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
Den ovenstående kode sætter elevens tastetryk ind i `_builder`, som er et `StringBuilder` objekt. Hvilket vil sige at den sammensætter tastetryk til tekst. ALLE tastetryk bliver logget! Det første den gør det er at tjekke om tasten er et bogstav eller et tal. Er det ikke tilfældet, f.eks. hvis der bliver trykket på mellemrums tasten, så vil den tage tastekoden og logge det som tastens talværdi omgivet af `[]` i logfilen. I dette tilfælde vil det producere `[32]`.

# Udklipslogger
At DDP havde muligheden for at kunne se hvad der ligger i udklipholderen var ikke overraskelse, da det var en af de ting vi blev informeret om under oplægget. Dog står dette ikke i den eksamensansvareliges brugervejledning.
```cs
protected override List<DataPackage> GetDataPackages()
{
  return new List<DataPackage>()
  {
    new DataPackage(DataPackage.ColTypeEnum.Clipb, new bool?(false), !Clipboard.ContainsText() ? Encoding.UTF8.GetBytes("no text") : Encoding.UTF8.GetBytes(Clipboard.GetText()), new DateTime?(DataPackageEnvelopeAwsReceiver.ServerTime), new long?((long) this.GetAndIncrementWorkSequence()))
  };
}
```
Dette tjekker om der er noget i udklipsholderen, er der ikke det logger den "no text". Hvis der er noget i udklipsholderen, gemmer den det i logfilen.

# Skærmbillede
På samme måde som der var to klasser ved keyloggeren er der også to klasser i spil ved skærmbillede funktionen. `ScreenCaptureTool` og `ScreenshotWorker` hvor workeren var den mest interessante ved keyloggeren, så er det her `ScreenCaptureTool` der er mest interessant.

```cs
public static Image CaptureScreenNew()
{
  Image result;
  try
  {
    Rectangle bounds = Screen.PrimaryScreen.Bounds;
    Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height);
    Size blockRegionSize = new Size(bitmap.Width, bitmap.Height);
    using (Graphics graphics = Graphics.FromImage(bitmap))
    {
      graphics.CopyFromScreen(0, 0, 0, 0, blockRegionSize);
      result = bitmap;
    }
  }
  catch (Exception ex)
  {
    StaticFileLogger.Current.LogEvent("ScreenCaptureTool.CaptureScreenNew()", "Exception taking screenshot", string.Format("Error is: '{0}'", ex.ToString()), EventLogEntryType.Information);
    result = ScreenCaptureTool.WriteExceptionToImage(ex);
  }
  return result;
}
```
Funktionen `CaptureScreenNew` forsøger først at tage et skærmbillede af hele skærmen. Hvis dette ikke lykkes har de skrevet funktionen `WriteExceptionToImage`, der vises her:
```cs
private static Image WriteExceptionToImage(Exception ex)
{
  Bitmap bitmap = new Bitmap(800, 600);
  Size size = bitmap.Size;
  size.Height -= 20;
  size.Width -= 20;
  RectangleF layoutRectangle = new RectangleF(new PointF(10f, 10f), size);
  using (Graphics graphics = Graphics.FromImage(bitmap))
  {
    GraphicsUnit graphicsUnit = GraphicsUnit.Pixel;
    graphics.FillRectangle(Brushes.Wheat, bitmap.GetBounds(ref graphicsUnit));
    graphics.SmoothingMode = SmoothingMode.AntiAlias;
    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
    graphics.DrawString(ex.ToString(), new Font("Tahoma", 10f), Brushes.Black, layoutRectangle);
  }
  return bitmap;
}
```
`WriteExceptionToImage` Skaber et billede der viser fejl-beskeden som et billede, dette er bare fejlsikring. Grunden til at de har valgt at gøre det sådan er i tilfældet af fejl.

Nedenfor ses et eksempel på hvordan en fejlbesked ville se ud.
![Eksempel på fejlbesked](/images/ss-ex.jpg)

```cs
private static ImageCodecInfo GetEncoder(ImageFormat format)
{
  ImageCodecInfo[] imageDecoders = ImageCodecInfo.GetImageDecoders();
  foreach (ImageCodecInfo imageCodecInfo in imageDecoders)
  {
    if (imageCodecInfo.FormatID == format.Guid)
    {
      return imageCodecInfo;
    }
  }
  return null;
}
```
`GetEncoder` får fat i encoder, der laver skærmbilledet om til et andet billedformat.

```cs
public static byte[] ImageToByteArray(Image imageIn, int jpgCompressionLevel = 30)
{
  MemoryStream memoryStream = new MemoryStream();
  EncoderParameters encoderParameters = new EncoderParameters(1);
  encoderParameters.Param[0] = new EncoderParameter(Encoder.Quality, jpgCompressionLevel);
  imageIn.Save(memoryStream, ScreenCaptureTool.GetEncoder(ImageFormat.Jpeg), encoderParameters);
  return memoryStream.ToArray();
}
```
`ImageToByteArray` tager imod to argumenter, et billede og et kompressionsniveau for jpg billedet. Den vigtigste del af denne funktion er `imageIn.Save((Stream) memoryStream, ScreenCaptureTool.GetEncoder(ImageFormat.Jpeg), encoderParams);`. Det der sker her er at billedet bliver konverteret til jpg format, derefter logget som en streng i logfilen eller sendt afsted til serveren.

# Netværkstrafik
DDP har også funktionen til at logge de hjemmesider eleven besøger under eksamensperioden. Programmet kan derved advare den eksamensansvarlige og advare om at eleven har besøgt forbudte sider.

Her til har de skabt en worker, der læser og gemmer den url som der bliver brugt af browseren.
```cs
protected override List<DataPackage> GetDataPackages()
{
  CurrentBrowserUrlsTool.GetHarvestedUrlsFromRunningProcessesAndEmptyTheList().ToList<string>().ForEach((Action<string>) (url => this._urls.Add(url)));
  List<string> list = this._urls.ToList<string>();
  list.Sort();
  byte[] bytes = Encoding.UTF8.GetBytes(string.Join(";", list));
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
Dette betyder at for windows versionen af DDP, tjekker de kun efter om browseren enten er Google Chrome, Firefox, Microsoft Edge eller Internet Explorer. De kan i denne version af DDP kan den ikke logge besøgte hjemmeside, hvis du bruger en anden browser.

I denne klasse har de også lavet en funktion der trækker url'en ud af en browser. Dette er en længere funktion ved navnet `GetURLFromProcess`, derfor går jeg hurtigt over den. Men det som den gør som noget af det første er at finde ud af om der overhovedet er en af de kendte browsere åben. Er dette tilfældet bruger den forskellige metoder til at skaffe url'en alt efter browseren.

# Netværkskonfiguration
DDP logger maskinens netværkskonfiguration. Den bruger dette information for at se om eleven er på skolens netværk og advare den eksamensansvarlige hvis eksaminanten ikke er på skolenetværket.

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
Programmet kan også se hvilke programmer eller processer der kører på computeren. Dette bruger den blandt andet til at se hvilken browser eksamenanden anvender. Den eksamensansvarlige kan sortliste processer der ikke må køres på eksamenandens maskine. Hvis et sortlistet program kører på maskinen, bliver den eksamensansvarlige advaret.

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
Den sætter alle processerne ind i en liste. Den tæller også antallet af processer og sætter dem ind i variablen `_lastNumberOfRunningProcesses`. Herefter kører den igennem alle processerne og skriver al informationen ind i variablen `s`.

# Virtuel maskine detektion
Programmet tjekker om det kører i en virtuel maskine. En virtuel maskine er et stykke software der emulerer en computer. Det vil sige at du kan have et separat styresystem kørende ved siden af et andet et. Denne beskyttelse er taget i brug fordi at en eksamenanden kan snyde hvis at eleven laver opgaven og kører DDP i den virtuelle maskine. Så kan DDP ikke overvåge elevens egentlige system, men kun den virtuelle maskine.
```cs
public bool AmIRunningInsideAVirtualMachine()
{
  bool isVm = false;
  try
  {
    foreach (ManagementBaseObject managementBaseObject in new ManagementObjectSearcher("root\\CIMV2", "SELECT * FROM Win32_BaseBoard").Get())
      flag = managementBaseObject["Manufacturer"].ToString().ToLower() == "microsoft corporation".ToLower();
    return isVm;
  }
  catch
  {
    return isVm;
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
Her er listen af kendte virtuel maskine processer.

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
Inde i DDP's konfigurationsfil finder man serverens url, deres api-kode og de workere der er aktiveret, samt workernes tidsinterval.

```xml
<dpvSettings>
  <timersConfig>
    <timers>
      <!--<timer secondsBetweenWork="123" workerToInstantiate="DpvClassLibrary.Workers.ClipboardTextWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null"/>-->
      <!--<timer secondsBetweenWork="51" workerToInstantiate="DpvClassLibrary.Workers.KeyloggerWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null"/>-->
      <timer secondsBetweenWork="61" workerToInstantiate="DpvClassLibrary.Workers.NetworkTrafficWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null" />
      <timer secondsBetweenWork="63" workerToInstantiate="DpvClassLibrary.Workers.NetworkConfigRetrieverWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null" />
      <timer secondsBetweenWork="61" workerToInstantiate="DpvClassLibrary.Workers.RunningProcessesWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null" />
      <timer secondsBetweenWork="30" workerToInstantiate="DpvClassLibrary.Workers.ScreenshotWorker, DpvClassLibrary, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null" />
    </timers>
  </timersConfig>
</dpvSettings>
```
De to timere sat op til udklipsloggeren og keyloggeren er begge udkommenteret, dette betyder at de ikke er taget i brug den version vi har fat i. `secondsBetweenWork` bestemmer hvor ofte den skal aktivere workeren.

# Server
Serveren er en del af Amazon AWS hvilket er en cloud løsning Amazon stiller til rådighed. Dataen bliver sendt over "https" hvilket vil sige at dataen er krypteret, og vil derfor ikke kunne opsamles gennem et man-in-the-middle angreb fra hackere.

# Fremtidige funktioner
Vi fandt mere kode der tydede på at der i en fremtidig version ville blive logget endnu mere data. Det vi fandt var nogle værdier, som sendes sammen med dataen, sådan at serveren ved hvad der blev sendt.

```cs
public enum ColTypeEnum
{
  Hbeat = 1,
  Netcf,
  Sshot,
  Vmdet,
  Plist,
  Clipb,
  Klog,
  Sites,
  Actapp,
  Usb,
  Bttrf
}
```

Her kan vi se nogle ting som der allerede er implementeret i programmet:
- `Hbeat`: Heartbeat
- `Netfc`: Netværkskonfiguration
- `Sshot`: Skærmbillede
- `Vmdet`: Virtuel maskine detektion
- `Plist`: Processer kørende
- `Clipb`: Udklipsholder
- `Sites`: Sider besøgt

Men her ser vi også flere uimplementerede funktioner, disse funktionnavne er tvetydelige, så deres funktion er ren spekulation:
- `Actapp`: Aktiv windue
- `Usb`: Isat usb enheder

Den sidste (`Bttrf`) kan vi ikke tyde. Det bedste bud vi har er tilkoblede bluetooth enheder.

## Regler og love
Fordi der er tale om sensitiv data, så er der selvfølgelig en lovgivning der skal følges. GDPR er den lovgivning der gælder når vi snakker om databehandling. Og det er artikel 6 stk. 1 der handler hvornår det er lovligt at behandle data.

1. Behandling er kun lovlig, hvis og i det omfang mindst ét af følgende forhold gør sig gældende:

    a) Den registrerede har givet samtykke til behandling af sine personoplysninger til et eller flere specifikke formål.

    b) Behandling er nødvendig af hensyn til opfyldelse af en kontrakt, som den registrerede er part i, eller af hensyn til gennemførelse af foranstaltninger, der træffes på den registreredes anmodning forud for indgåelse af en kontrakt.

    c) Behandling er nødvendig for at overholde en retlig forpligtelse, som påhviler den dataansvarlige.

    d) Behandling er nødvendig for at beskytte den registreredes eller en anden fysisk persons vitale interesser.

    e) Behandling er nødvendig af hensyn til udførelse af en opgave i samfundets interesse eller som henhører under offentlig myndighedsudøvelse, som den dataansvarlige har fået pålagt.

    f) Behandling er nødvendig for, at den dataansvarlige eller en tredjemand kan forfølge en legitim interesse, medmindre den registreredes interesser eller grundlæggende rettigheder og frihedsrettigheder, der kræver beskyttelse af personoplysninger, går forud herfor, navnlig hvis den registrerede er et barn.

    Første afsnit, litra f), gælder ikke for behandling, som offentlige myndigheder foretager som led i udførelsen af deres opgaver.

(Kilde: [gdpr.dk](https://gdpr.dk/databeskyttelsesforordningen/kapitel-2-principper/artikel-6-lovlig-behandling/))

Det første man læser når ser artikel 6 stk. 1(a), hvor der står at det er okay hvis der er givet samtykke. Har man ikke givet samtykke så er det ulovligt, og det er nok dette de fleste folk tænker på når de siger at der er ulovligt. Men Undervisningsministeriet har hjemmel i forhold til stk. 1 (e) da man vil kunne argumentere for at det er i samfundets bedste interresse at mindske mængden af snyd.

> Ja, behandlingen har hjemmel i den myndighedsopgave, som er pålagt Styrelsen for Undervisning og Kvalitet såvel som uddannelsesinstitutionerne (jf. Databeskyttelsesforordningen (GDPR) artikel 6 stk. 1 (e)) i forhold til at håndhæve § 20 i ” Bekendtgørelse om prøver og eksamen i de almene og studieforberedende ungdoms- og voksenuddannelser” og i §§ 5-7 i ”Bekendtgørelse om visse regler om prøver og eksamen i de gymnasiale uddannelser”.

(Kilde: [Undervisningsministeriets spørgsmål og svar om prøvevagten](https://uvm.dk/gymnasiale-uddannelser/proever-og-eksamen/netproever/den-digitale-proevevagt/spoergsmaal-og-svar?fbclid=IwAR3YNOq9UrCXZM24xDnRydV8RTYzfqoXFcJrLBUnyIMNNJOLJN1HZpbXr_I))


## Diskussion
At mulighederne for at snyde bliver større og større i takt med at vi bliver mere og mere forbundet gennem internettet skal ikke glemmes. Og grundlaget for sådan et program er som sådan gode nok, men problemet ligger i udførslen. Vi som elever, og ikke mindst borgerer, burde ikke skulle installere et stykke spyware på vores private enhed. Dette er der mange der mener er en krænkelse af privatlivet.
Problemet ligger i at for at softwaren ikke bliver blokeret af anti-virus software så bliver dette bibliotek de har skrevet, pludseligt det bedste spyware/virus bibliotek af bruge. Et andet problem ligger i at de har valgt at inkludere en keylogger i programmet. Deres metode gør at i det tilfælde at du logger ind på en side, så har undervisningsministeriet adgang til den konto. Hvis en hacker fandt vej ind til deres servere ville de pludselig have dit bruger-id og kode til nem-id f.eks.

Undervisningsministeriet har lavet en FAQ med Danske Gymnasieelevers Sammenslutning, hvor de besvarer flere bekymringer. Her indrømmer de også at der er en keylogger i DDP, men at den ikke er aktiveret endnu. Deres plan med den er at den skal bruge til at tjekke op på det antal anslag der er skrevet i opgaven. De fortæller også at dataen der bliver gemt er krypteret på serveren, hvilket lyder til at være sandfærdigt eftersom at det bliver sendt afsted krypteret. De fortæller også at den ikke henter filer der ligger på din pc, hvilket passer med det vi har fundet i kildekoden.
Efter FAQ'en opdaterede de også programmet til ikke at tage screenshots før eksamenen begyndte.
([Link til FAQ][uvm-faq])

Sådan som keyloggeren er implementeret lige nu, så indsamler den alle tastetryk også dem der ikke vedrører opgaven. Hvis keyloggeren kun loggede tastestryk der blev brugt i Word eller Open-office, så ville denne sikkerheds risiko ikke længere være relevant. De har allerede implementeret kode der kan se processerne der køre, samt se hvilket vinduet der er aktivt. Så ville de også kunne bruge det data til at sammenligne antallet af anslag.


[uvm-faq]: https://www.facebook.com/notes/danske-gymnasieelevers-sammenslutning/hvad-er-den-digitale-pr%C3%B8vevagt-faq/10156886822478956/
[uvm-info]: https://uvm.dk/gymnasiale-uddannelser/proever-og-eksamen/netproever/den-digitale-proevevagt/om-den-digitale-proevevagt
[fb-debat]: https://www.facebook.com/jeanette.feldballe/posts/10214797289978061
[alex-norup]: https://www.alexandernorup.com/DigitalProvevagt?fbclid=IwAR2Hp_fDZHZh4FALcVJCnciM-w3z1kMafh_bilPboIlLpeylNJhdKIvYCYY
