---
layout: post
title:  "Den Digitale Prøvevagt situation"
date:   2019-03-01 11:47:34 +0100
categories: Write-ups
---
## Indledning
Som mange nok ved har Undervisningsministeriet besluttet at der skal fokuseres mere på snyd, og forbyggelse af dette. Dette resulterer i at for at kunne gå op til en eksamen, så skal der downloades og installeres et stykke software der kan holde øje med hver enkelte pc. Undervisningsministeriet har gjordt det til et krav at bruge dette software ved navnet "Den Digitale Prøvevagt", forkortet til "DDP".
Programmet virker, i skrivende stund, kun til Windows og MacOS. Har man et andet styresystem en de to f.eks. en Linux distribution får eleven enten en låne bærbar tildelt, eller så tager de prøven med skærpet tilsyn. Når prøven slutter vil programmet stoppe. Herefter kan eleven vælge og afinstallere DDP, eller lade være hvis der er flere skriftlige prøver han/hun skal til.
Nægter man at downloade og installere DDP så kan man ikke gå op til eksamenen og derved dumper man.
(Kilde: [Undervisningsministeriets side om prøvevagten][uvm-info])

Som så mange andre gymnasie elever, synes jeg det er en meget forkert tilgang. At vi skal installere et stykke software der i bund og grund er spyware, for at vi kan komme op til en skriftlig eksamen. Ifølge en debat på facebook([link][fb-debat]), er der flere ting som virker skummelt ved programmet. Jeg har derfor, i samarbejde med en af mine venner, forsøgt at komme tilbunds i hvad dette program helt præcist gør.

## Metode
Vi debuggede koden ved hjælp af samme metode som [Alexander Norup][alex-norup]. Windows versionen af DDP er programmeret i Windows' .NET framework i sproget C#. For at skaffe kildekoden til programmet, brugte vi en C# decompiler for at nærlæse koden. Det kørte vi på DDPs exe fil, som gav os en læsbar kildekode.

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
- Browser type
- Kørende programmer på maskinen
- Virtuel maskine checker
- Maskine fingeraftryk
- Server(Som bliver brugt at Undervisningsministeriet)

DDP fungere ved af såkaldte "workers", der er en til hver af de indbyggede funktioner programmet har. De sender den data de indsamler til en "CommunicationManager", som sender det videre til en server.

# Keylogger
Ï det oplæg omkring DDP vi fik på fik vi ingenting at om der var en keylogger i programmet. Havde læst om at der var en på Alexander Norups [blog][alex-norup], var lidt skeptisk hvilket også var en af motivationerne til at tjekke efter selv.
Keyloggeren består af to klasser, `KeyloggerHelper.cs` og `KeyloggerWorker.cs`. `KeyloggerHelper.cs` er det bibliotek som de har skrevet for at kunne indsamle tastetryk.`KeyloggerWorker.cs`står for at udføre selve indsamlingen og sende det til "CommunicationManager".

#### KeyloggerWorker.cs
Den mest interessante af de to klasser er `KeyloggerWorker.cs`, fordi det er den der gør det meste af arbejdet.

```cs
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

# Netværkstrafik

# Browser type

# Kørende programmer på maskinen

# Virtuel maskine checker

# Maskine fingeraftryk

# Server

## Regler og love

## Konklusion



To add new posts, simply add a file in the `_posts` directory that follows the convention `YYYY-MM-DD-name-of-post.ext` and includes the necessary front matter. Take a look at the source for this post to get an idea about how it works.

Jekyll also offers powerful support for code snippets:

{% highlight ruby %}
def print_hi(name)
  puts "Hi, #{name}"
end
print_hi('Tom')
#=> prints 'Hi, Tom' to STDOUT.
{% endhighlight %}

Check out the [Jekyll docs][jekyll-docs] for more info on how to get the most out of Jekyll. File all bugs/feature requests at [Jekyll’s GitHub repo][jekyll-gh]. If you have questions, you can ask them on [Jekyll Talk][jekyll-talk].

[jekyll-docs]: https://jekyllrb.com/docs/home
[jekyll-gh]:   https://github.com/jekyll/jekyll
[jekyll-talk]: https://talk.jekyllrb.com/
[uvm-info]: https://uvm.dk/gymnasiale-uddannelser/proever-og-eksamen/netproever/den-digitale-proevevagt/om-den-digitale-proevevagt
[fb-debat]: https://www.facebook.com/jeanette.feldballe/posts/10214797289978061
[alex-norup]: https://www.alexandernorup.com/DigitalProvevagt?fbclid=IwAR2Hp_fDZHZh4FALcVJCnciM-w3z1kMafh_bilPboIlLpeylNJhdKIvYCYY
