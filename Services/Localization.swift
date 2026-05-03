//
//  Localization.swift
//  Rödbuss
//

import SwiftUI

// MARK: - Current language environment

private struct CurrentLanguageKey: EnvironmentKey {
    static let defaultValue: String = "English"
}

extension EnvironmentValues {
    var currentLanguage: String {
        get { self[CurrentLanguageKey.self] }
        set { self[CurrentLanguageKey.self] = newValue }
    }
}

// MARK: - Localization dictionary (English + Swedish)

enum L10n {
    private static let strings: [String: [String: String]] = [
        "English": [
            "settings.title": "Settings",
            "settings.preferences": "Preferences",
            "settings.darkMode": "Dark mode",
            "settings.darkModeSubtitle": "Use dark appearance",
            "settings.clearHistory": "Clear history",
            "settings.clearHistorySubtitle": "Clear last search and cached data",
            "settings.sleepTime": "API sleep time",
            "settings.sleepTimeSubtitle": "Choose when Rödbuss goes to sleep",
            "settings.language": "Language",
            "settings.languageSubtitle": "App language",
            "settings.support": "Support",
            "settings.helpSupport": "Help and support",
            "settings.helpSupportSubtitle": "Get help and contact support",
            "settings.apiInfo": "API info",
            "settings.termsPrivacy": "Terms and privacy",
            "settings.termsPrivacySubtitle": "View terms and privacy policy",
            "settings.about": "About",
            "settings.aboutSubtitle": "App version and information",
            "settings.clearHistoryAlertTitle": "Clear history?",
            "settings.clearHistoryAlertMessage": "This will clear your last search and cached stop data. Your saved rides will not be affected.",
            "settings.clear": "Clear",
            "settings.cancel": "Cancel",
            "settings.done": "Done",
            "language.title": "Language",
            "language.english": "English",
            "language.swedish": "Swedish",
            "settings.trafiklabKey": "Trafiklab API key",
            "settings.trafiklabKeySubtitle": "For live bus position on map (free at trafiklab.se)",
            "termsPrivacy.title": "Terms and Privacy",
            "termsPrivacy.tabTerms": "Terms",
            "termsPrivacy.tabPrivacy": "Privacy",
            "termsPrivacy.tabDisclaimer": "Disclaimer",
            "termsPrivacy.termsContent": """
            TERMS OF USE

            Last Updated: April 24, 2026

            Welcome to Rödbuss. These Terms of Use ("Terms") govern your access to and use of the Rödbuss mobile application ("App"). By using the App, you agree to be bound by these Terms.

            1. ACCEPTANCE OF TERMS
            By downloading, installing, or using Rödbuss, you acknowledge that you have read, understood, and agree to be bound by these Terms and our Privacy Policy.

            2. DESCRIPTION OF SERVICE
            Rödbuss helps you find and monitor public bus departures, with focus on SL traffic data. The App allows you to:
            - Search departures from selected stops
            - Filter by route direction and destination
            - Save routes in My Rides
            - Pin one route as your dashboard favorite
            - View upcoming departures and route details on map
            - Configure app preferences such as language and refresh behavior

            3. USER ACCOUNTS
            Rödbuss does not require account creation. Your saved routes and preferences are stored on your device.

            4. ACCEPTABLE USE
            You agree to use the App only for lawful purposes and in accordance with these Terms. You agree not to:
            - Use the App for unlawful activity
            - Attempt unauthorized access to the App or related systems
            - Interfere with App functionality or availability
            - Use automated systems to abuse data requests

            5. THIRD-PARTY DATA
            The App may display public transport information from third-party providers (such as Trafiklab/SL). Availability, accuracy, and timeliness of that data are controlled by those providers.

            6. INTELLECTUAL PROPERTY
            The App and its original content, design, and software are protected by applicable intellectual property laws.

            7. LIMITATION OF LIABILITY
            Rödbuss is provided "as is" without warranties of any kind. We do not guarantee uninterrupted service or error-free operation. To the extent permitted by law, we are not liable for indirect, incidental, or consequential damages.

            8. CHANGES TO TERMS
            We may update these Terms from time to time. Continued use of the App after changes are posted means you accept the updated Terms.

            9. CONTACT
            For support or legal/privacy questions, use the support section available in the app settings.
            """,
            "termsPrivacy.privacyContent": """
            PRIVACY POLICY

            Last Updated: April 24, 2026

            At Rödbuss, we aim to keep your information private and minimal.

            1. LOCAL APP DATA
            Rödbuss stores app data locally on your device, including:
            - Saved rides and dashboard selection
            - Last search state
            - UI preferences (such as language and appearance)
            - Optional Trafiklab API key you enter in settings

            2. NO USER ACCOUNT TRACKING
            Rödbuss does not require user login and does not build user profiles.

            3. NETWORK REQUESTS
            To show departures, the app sends stop/site requests to transport data providers (for example Trafiklab APIs). These requests are necessary for core functionality.

            4. DATA SHARING
            We do not sell your personal data. The app only exchanges the minimum request data needed to fetch transport information from providers you use.

            5. DATA CONTROL
            You control your local app data:
            - Remove saved rides in My Rides
            - Clear app history/cache from settings
            - Remove or update API key in settings

            6. SECURITY
            Local data security depends on your device protections (passcode, biometrics, OS security model). Keep your device updated and protected.

            7. CHILDREN'S PRIVACY
            Rödbuss is not designed to collect personal data from children.

            8. POLICY CHANGES
            We may update this Privacy Policy and will publish changes in the app.

            9. CONTACT
            For privacy questions, use the support section in settings.
            """,
            "termsPrivacy.disclaimerContent": """
            DISCLAIMER

            Last Updated: April 24, 2026

            1. INFORMATIONAL PURPOSE
            Rödbuss is an informational companion for public transport departures. It is not an official transport operator service.

            2. NO GUARANTEE OF ACCURACY
            Departure times, delays, and route details depend on third-party data feeds and may be delayed, incomplete, or inaccurate.

            3. NO WARRANTY
            The App is provided "as is" and "as available" with no express or implied warranties, including merchantability, fitness for a particular purpose, or non-infringement.

            4. USER RESPONSIBILITY
            You are responsible for verifying critical travel details (departure platform, real-time disruptions, route changes) through official channels when needed.

            5. LIMITATION OF LIABILITY
            To the maximum extent allowed by law, Rödbuss is not liable for missed trips, delays, losses, or damages resulting from use of the App or reliance on its information.

            6. THIRD-PARTY SERVICES
            The app may rely on third-party APIs and map services. Their availability and terms are outside our control.

            7. APP CHANGES
            We may modify, suspend, or discontinue features at any time without notice.

            8. ACCEPTANCE
            By using Rödbuss, you acknowledge and accept this Disclaimer.
            """,
            "helpSupport.title": "Help and Support",
            "helpSupport.close": "Close",
            "helpSupport.contactSupportTitle": "Contact support",
            "helpSupport.messageSentTitle": "Message sent",
            "helpSupport.messageSentBody": "Thanks for contacting Rödbuss support. We will get back to you as soon as possible.",
            "helpSupport.landingTitle": "Need help with Rödbuss?",
            "helpSupport.landingLine1": "Questions about departures, saved rides,",
            "helpSupport.landingLine2": "map behavior, API key setup,",
            "helpSupport.landingLine3": "or app settings? We're here to help.",
            "helpSupport.emailLabel": "Email",
            "helpSupport.websiteLabel": "Website",
            "helpSupport.contactFormButton": "Contact form",
            "helpSupport.replyTime": "We usually reply within 24 hours.",
            "helpSupport.fullNameHeader": "Your full name",
            "helpSupport.fullNamePlaceholder": "Full name",
            "helpSupport.emailHeader": "Your email",
            "helpSupport.emailPlaceholder": "Email",
            "helpSupport.subjectHeader": "Subject",
            "helpSupport.subjectPlaceholder": "What do you need help with?",
            "helpSupport.descriptionHeader": "Description",
            "helpSupport.allFieldsRequired": "All fields are required.",
            "helpSupport.send": "Send",
            "about.title": "About",
            "about.versionPrefix": "Version",
            "about.sectionAppTitle": "About Rödbuss",
            "about.sectionAppBody1": "Rödbuss helps you quickly find bus departures in the Stockholm area and keep your most used routes in one place. Search from and to stops, save rides for faster access, and pin your favorite route so the next departures are always easy to check.",
            "about.sectionAppBody2": "The app focuses on a fast daily commute workflow: search, save, monitor, and go. With map support and live route context, Rödbuss is built to reduce friction when planning everyday trips.",
            "about.sectionCompanyTitle": "About ABASHELARI",
            "about.sectionCompanyBody1": "At ABASHELARI, we believe in creating software that makes everyday life simpler, smarter, and more enjoyable. Our mission is to develop innovative digital solutions that blend creativity with technology, offering users tools that are intuitive, reliable, and engaging.",
            "about.sectionCompanyBody2": "Whether it's travel apps, educational tools, or lifestyle products, ABASHELARI is dedicated to building high-quality experiences that solve real problems and bring everyday value.",
            "about.sectionCompanyBody3": "Driven by curiosity and continuous improvement, ABASHELARI is committed to creating thoughtful products that people trust and enjoy using.",
            "about.appName": "Rödbuss",
            "about.tagline": "Bus departures for Stockholm area.",
            "tab.map": "Dashboard",
            "map.subtitle": "Saved stops",
            "map.currentLocation": "Current location",
            "map.nearbyBusStops": "Nearby bus stops",
            "map.loadingMap": "Loading map…",
            "map.locationDenied": "Location access is off. Enable it in Settings to see nearby stops.",
            "map.injectToFrom": "Set as Start",
            "map.injectToTo": "Set as Destination",
            "map.searchNow": "Search now",
            "map.searchNowPromptTitle": "Search now",
            "map.searchNowPromptMessage": "From and To are set. Search for departures?",
            "map.searchNowPromptMessageFormat": "%@ to %@, start search?",
            "tab.myRides": "My Rides",
            "tab.dashboard": "Favorite",
            "tab.search": "Search",
            "tab.settings": "Settings",
            "search.title": "Find a bus",
            "search.from": "From",
            "search.to": "To",
            "search.selectOrigin": "Select origin",
            "search.selectDestination": "Select destination",
            "search.searchButton": "Search",
            "search.save": "Save",
            "search.saved": "Saved",
            "search.noResults": "No results, try to modify the search",
            "search.loading": "Loading…",
            "search.loadingStops": "Loading stops…",
            "search.busesFrom": "Buses from %@",
            "search.busesFromTo": "%@ to %@",
            "myRides.title": "My Rides",
            "myRides.emptyTitle": "No saved rides",
            "myRides.emptySubtitle": "Tap a result in Find a bus, then Save to My Rides.",
            "myRides.dashboard": "Favorite",
            "myRides.displayInDashboard": "Display in Favorite",
            "myRides.removeFromDashboard": "Remove from Favorite",
            "dashboard.title": "Favorite",
            "dashboard.emptyTitle": "Favorite",
            "dashboard.emptySubtitle": "Open My Rides and choose a route to set as your favorite.",
            "dashboard.nextDepartures": "Next departures",
            "dashboard.noDepartures": "No departures",
            "dashboard.noDeparturesForLine": "Currently there are no departures for line %@",
            "dashboard.loading": "Loading…",
            "dashboard.openSLApp": "Open SL app",
            "dashboard.openMap": "Show map",
            "rideSaved.title": "Ride saved",
            "rideSaved.message": "Ride saved to My Rides.",
            "rideSaved.savedToMyRides": "Saved to \"My rides\"",
            "rideSaved.removedFromMyRides": "Removed from \"My rides\"",
            "rideSaved.dontShowAgain": "Don't show again",
            "rideExists.title": "Ride already exists",
            "rideExists.message": "This route with this line is already in My Rides.",
            "common.ok": "OK",
            "common.retry": "Retry",
            "common.destination": "Destination",
            "common.bus": "Bus",
            "common.cancelled": "Cancelled",
            "myRides.onDashboard": "On Favorite",
            "myRides.addToDashboard": "On favorite",
            "myRides.rideName": "Ride name",
            "myRides.lineFormat": "Line %@",
            "myRides.currentlyNoTime": "Currently no time",
            "myRides.noInformation": "No information",
            "map.unavailable": "Map unavailable",
            "map.unavailableDescription": "Route coordinates could not be loaded for this ride.",
            "map.busStatusNoKey": "Bus: Add API key in Settings",
            "map.busStatusLoading": "Bus: Loading…",
            "map.busStatusLive": "Bus: Live",
            "map.busStatusError": "Bus: Unavailable",
            "map.busRefresh": "Refresh",
            "bus.towards": "Towards %@",
            "time.now": "Now",
            "sleepPopup.title": "Rödbuss went to sleep.",
            "sleepPopup.wakeUp": "Wake up!",
        ],
        "Swedish": [
            "settings.title": "Inställningar",
            "settings.preferences": "Preferenser",
            "settings.darkMode": "Mörkt läge",
            "settings.darkModeSubtitle": "Använd mörkt utseende",
            "settings.clearHistory": "Rensa historik",
            "settings.clearHistorySubtitle": "Rensa senaste sökning och cachad data",
            "settings.sleepTime": "API-vilotid",
            "settings.sleepTimeSubtitle": "Välj när Rödbuss går i viloläge",
            "settings.language": "Språk",
            "settings.languageSubtitle": "Appens språk",
            "settings.support": "Support",
            "settings.helpSupport": "Hjälp och support",
            "settings.helpSupportSubtitle": "Få hjälp och kontakta support",
            "settings.apiInfo": "API-info",
            "settings.termsPrivacy": "Villkor och integritet",
            "settings.termsPrivacySubtitle": "Läs villkor och integritetspolicy",
            "settings.about": "Om",
            "settings.aboutSubtitle": "Appversion och information",
            "settings.clearHistoryAlertTitle": "Rensa historik?",
            "settings.clearHistoryAlertMessage": "Detta rensar din senaste sökning och cachad hållplatsdata. Dina sparade resor påverkas inte.",
            "settings.clear": "Rensa",
            "settings.cancel": "Avbryt",
            "settings.done": "Klar",
            "language.title": "Språk",
            "language.english": "Engelska",
            "language.swedish": "Svenska",
            "settings.trafiklabKey": "Trafiklab API-nyckel",
            "settings.trafiklabKeySubtitle": "För live bussposition på kartan (gratis på trafiklab.se)",
            "termsPrivacy.title": "Villkor och integritet",
            "termsPrivacy.tabTerms": "Villkor",
            "termsPrivacy.tabPrivacy": "Integritet",
            "termsPrivacy.tabDisclaimer": "Ansvarsfriskrivning",
            "termsPrivacy.termsContent": """
            ANVÄNDARVILLKOR

            Senast uppdaterad: 24 april 2026

            Välkommen till Rödbuss. Dessa användarvillkor ("Villkor") reglerar din åtkomst till och användning av mobilappen Rödbuss ("Appen"). Genom att använda appen godkänner du dessa villkor.

            1. GODKÄNNANDE AV VILLKOR
            Genom att ladda ner, installera eller använda Rödbuss bekräftar du att du har läst, förstått och godkänner dessa villkor samt vår integritetspolicy.

            2. TJÄNSTEBESKRIVNING
            Rödbuss hjälper dig att hitta och följa bussavgångar med fokus på SL-data. Appen låter dig:
            - Söka avgångar från valda hållplatser
            - Filtrera efter riktning och destination
            - Spara rutter i Mina resor
            - Nåla fast en rutt som favorit
            - Visa kommande avgångar och ruttinformation på karta
            - Anpassa appinställningar som språk och uppdateringsbeteende

            3. ANVÄNDARKONTON
            Rödbuss kräver inget användarkonto. Dina sparade rutter och inställningar lagras på din enhet.

            4. TILLÅTEN ANVÄNDNING
            Du samtycker till att använda appen endast för lagliga ändamål och i enlighet med dessa villkor. Du får inte:
            - Använda appen för olaglig verksamhet
            - Försöka få obehörig åtkomst till appen eller relaterade system
            - Störa appens funktion eller tillgänglighet
            - Använda automatiserade system för att missbruka dataförfrågningar

            5. TREDJEPARTSDATA
            Appen kan visa kollektivtrafikinformation från tredjepartsleverantörer (t.ex. Trafiklab/SL). Tillgänglighet, korrekthet och aktualitet styrs av dessa leverantörer.

            6. IMMATERIELLA RÄTTIGHETER
            Appen och dess ursprungliga innehåll, design och programvara skyddas av tillämpliga immaterialrättsliga lagar.

            7. ANSVARSBEGRÄNSNING
            Rödbuss tillhandahålls i "befintligt skick" utan garantier av något slag. Vi garanterar inte oavbruten drift eller felfri funktion. I den utsträckning lagen tillåter ansvarar vi inte för indirekta eller följdskador.

            8. ÄNDRINGAR AV VILLKOREN
            Vi kan uppdatera dessa villkor från tid till annan. Fortsatt användning av appen efter publicerade ändringar innebär att du accepterar de uppdaterade villkoren.

            9. KONTAKT
            För support eller juridiska/integritetsfrågor, använd supportsektionen i appens inställningar.
            """,
            "termsPrivacy.privacyContent": """
            INTEGRITETSPOLICY

            Senast uppdaterad: 24 april 2026

            På Rödbuss vill vi hantera din information så privat och minimalt som möjligt.

            1. LOKAL APPDATA
            Rödbuss lagrar appdata lokalt på din enhet, inklusive:
            - Sparade resor och favoritval
            - Senaste sökstatus
            - UI-inställningar (som språk och utseende)
            - Valfri Trafiklab API-nyckel som du anger i inställningar

            2. INGEN KONTOBASERAD SPÅRNING
            Rödbuss kräver ingen inloggning och bygger inga användarprofiler.

            3. NÄTVERKSFÖRFRÅGNINGAR
            För att visa avgångar skickar appen hållplatsförfrågningar till trafikdataleverantörer (t.ex. Trafiklab API). Dessa förfrågningar krävs för kärnfunktionalitet.

            4. DATDELNING
            Vi säljer inte dina personuppgifter. Appen utbyter endast den minsta mängd förfrågningsdata som behövs för att hämta trafikinformation från de leverantörer du använder.

            5. DATAKONTROLL
            Du kontrollerar din lokala appdata:
            - Ta bort sparade resor i Mina resor
            - Rensa historik/cache i inställningar
            - Ta bort eller uppdatera API-nyckel i inställningar

            6. SÄKERHET
            Säkerheten för lokal data beror på enhetens skydd (kodlås, biometrik, operativsystemets säkerhetsmodell). Håll enheten uppdaterad och skyddad.

            7. BARNS INTEGRITET
            Rödbuss är inte utformad för att samla in personuppgifter från barn.

            8. ÄNDRINGAR I POLICYN
            Vi kan uppdatera denna integritetspolicy och publicerar då ändringarna i appen.

            9. KONTAKT
            För integritetsfrågor, använd supportsektionen i inställningar.
            """,
            "termsPrivacy.disclaimerContent": """
            ANSVARSFRISKRIVNING

            Senast uppdaterad: 24 april 2026

            1. INFORMATIONSSYFTE
            Rödbuss är ett informationsstöd för kollektivtrafikens avgångar. Appen är inte en officiell operatörstjänst.

            2. INGEN GARANTI FÖR KORREKTHET
            Avgångstider, förseningar och ruttinformation beror på tredjepartsdatakällor och kan vara fördröjda, ofullständiga eller felaktiga.

            3. INGEN GARANTI
            Appen tillhandahålls i "befintligt skick" och "i mån av tillgång" utan uttryckliga eller underförstådda garantier.

            4. ANVÄNDARENS ANSVAR
            Du ansvarar för att verifiera viktiga reseuppgifter (hållplatsläge, driftstörningar, ruttändringar) i officiella kanaler vid behov.

            5. ANSVARSBEGRÄNSNING
            I den utsträckning lagen tillåter ansvarar Rödbuss inte för missade resor, förseningar, förluster eller skador som uppstår vid användning av appen eller tillit till dess information.

            6. TREDJEPARTSTJÄNSTER
            Appen kan vara beroende av tredjeparts-API:er och karttjänster. Deras tillgänglighet och villkor ligger utanför vår kontroll.

            7. ÄNDRINGAR I APPEN
            Vi kan när som helst ändra, pausa eller avveckla funktioner utan förhandsbesked.

            8. GODKÄNNANDE
            Genom att använda Rödbuss bekräftar du att du har läst och accepterar denna ansvarsfriskrivning.
            """,
            "helpSupport.title": "Hjälp och support",
            "helpSupport.close": "Stäng",
            "helpSupport.contactSupportTitle": "Kontakta support",
            "helpSupport.messageSentTitle": "Meddelande skickat",
            "helpSupport.messageSentBody": "Tack för att du kontaktar Rödbuss support. Vi återkommer så snart som möjligt.",
            "helpSupport.landingTitle": "Behöver du hjälp med Rödbuss?",
            "helpSupport.landingLine1": "Frågor om avgångar, sparade resor,",
            "helpSupport.landingLine2": "kartbeteende, API-nyckel eller",
            "helpSupport.landingLine3": "appinställningar? Vi hjälper gärna till.",
            "helpSupport.emailLabel": "E-post",
            "helpSupport.websiteLabel": "Webbplats",
            "helpSupport.contactFormButton": "Kontaktformulär",
            "helpSupport.replyTime": "Vi svarar oftast inom 24 timmar.",
            "helpSupport.fullNameHeader": "Ditt fullständiga namn",
            "helpSupport.fullNamePlaceholder": "Fullständigt namn",
            "helpSupport.emailHeader": "Din e-post",
            "helpSupport.emailPlaceholder": "E-post",
            "helpSupport.subjectHeader": "Ämne",
            "helpSupport.subjectPlaceholder": "Vad behöver du hjälp med?",
            "helpSupport.descriptionHeader": "Beskrivning",
            "helpSupport.allFieldsRequired": "Alla fält måste fyllas i.",
            "helpSupport.send": "Skicka",
            "about.title": "Om",
            "about.versionPrefix": "Version",
            "about.sectionAppTitle": "Om Rödbuss",
            "about.sectionAppBody1": "Rödbuss hjälper dig att snabbt hitta bussavgångar i Stockholmsområdet och samla dina mest använda rutter på ett ställe. Sök från och till hållplatser, spara resor för snabb åtkomst och markera en favorit så att nästa avgångar alltid är enkla att se.",
            "about.sectionAppBody2": "Appen fokuserar på ett snabbt pendlingsflöde: sök, spara, följ och åk. Med kartstöd och live-kontekst för rutter är Rödbuss byggd för att minska friktion i din vardagsresa.",
            "about.sectionCompanyTitle": "Om ABASHELARI",
            "about.sectionCompanyBody1": "På ABASHELARI tror vi på att skapa programvara som gör vardagen enklare, smartare och roligare. Vårt uppdrag är att utveckla innovativa digitala lösningar som kombinerar kreativitet och teknik, med verktyg som är intuitiva, pålitliga och engagerande.",
            "about.sectionCompanyBody2": "Oavsett om det gäller reseappar, utbildningsverktyg eller livsstilsprodukter är ABASHELARI dedikerade till att bygga upplevelser av hög kvalitet som löser verkliga problem och skapar vardagsvärde.",
            "about.sectionCompanyBody3": "Drivna av nyfikenhet och ständig förbättring strävar ABASHELARI efter att skapa genomtänkta produkter som människor litar på och tycker om att använda.",
            "about.appName": "Rödbuss",
            "about.tagline": "Bussavgångar i Stockholmsområdet.",
            "tab.map": "Dashboard",
            "map.subtitle": "Sparade hållplatser",
            "map.currentLocation": "Nuvarande plats",
            "map.nearbyBusStops": "Närliggande busshållplatser",
            "map.loadingMap": "Laddar karta…",
            "map.locationDenied": "Platsåtkomst är avstängd. Aktivera i Inställningar för att se närliggande hållplatser.",
            "map.injectToFrom": "Ange som start",
            "map.injectToTo": "Ange som destination",
            "map.searchNow": "Sök nu",
            "map.searchNowPromptTitle": "Sök nu",
            "map.searchNowPromptMessage": "Från och Till är valda. Sök avgångar?",
            "map.searchNowPromptMessageFormat": "%@ till %@, starta sökning?",
            "tab.myRides": "Mina resor",
            "tab.dashboard": "Favorit",
            "tab.search": "Sök",
            "tab.settings": "Inställningar",
            "search.title": "Hitta buss",
            "search.from": "Från",
            "search.to": "Till",
            "search.selectOrigin": "Välj ursprung",
            "search.selectDestination": "Välj destination",
            "search.searchButton": "Sök",
            "search.save": "Spara",
            "search.saved": "Sparad",
            "search.noResults": "Inga resultat, försök ändra sökningen",
            "search.loading": "Laddar…",
            "search.loadingStops": "Laddar hållplatser…",
            "search.busesFrom": "Bussar från %@",
            "search.busesFromTo": "%@ till %@",
            "myRides.title": "Mina resor",
            "myRides.emptyTitle": "Inga sparade resor",
            "myRides.emptySubtitle": "Tryck på ett resultat i Hitta buss och sedan Spara till Mina resor.",
            "myRides.dashboard": "Favorit",
            "myRides.displayInDashboard": "Visa i Favorit",
            "myRides.removeFromDashboard": "Ta bort från Favorit",
            "dashboard.title": "Favorit",
            "dashboard.emptyTitle": "Favorit",
            "dashboard.emptySubtitle": "Öppna Mina resor och välj en rutt att spara som favorit.",
            "dashboard.nextDepartures": "Nästa avgångar",
            "dashboard.noDepartures": "Inga avgångar",
            "dashboard.noDeparturesForLine": "Det finns för närvarande inga avgångar för linje %@",
            "dashboard.loading": "Laddar…",
            "dashboard.openSLApp": "Öppna SL-appen",
            "dashboard.openMap": "Visa karta",
            "rideSaved.title": "Resa sparad",
            "rideSaved.message": "Resan sparad till Mina resor.",
            "rideSaved.savedToMyRides": "Sparad till \"Mina resor\"",
            "rideSaved.removedFromMyRides": "Borttagen från \"Mina resor\"",
            "rideSaved.dontShowAgain": "Visa inte igen",
            "rideExists.title": "Resan finns redan",
            "rideExists.message": "Denna rutt med denna linje finns redan i Mina resor.",
            "common.ok": "OK",
            "common.retry": "Försök igen",
            "common.destination": "Destination",
            "common.bus": "Buss",
            "common.cancelled": "Inställd",
            "myRides.onDashboard": "På Favorit",
            "myRides.addToDashboard": "På favorit",
            "myRides.rideName": "Resnamn",
            "myRides.lineFormat": "Linje %@",
            "myRides.currentlyNoTime": "Ingen tid just nu",
            "myRides.noInformation": "Ingen information",
            "map.unavailable": "Kartan är inte tillgänglig",
            "map.unavailableDescription": "Ruttkoordinater kunde inte laddas för denna resa.",
            "map.busStatusNoKey": "Buss: Lägg till API-nyckel i Inställningar",
            "map.busStatusLoading": "Buss: Laddar…",
            "map.busStatusLive": "Buss: Live",
            "map.busStatusError": "Buss: Ej tillgänglig",
            "map.busRefresh": "Uppdatera",
            "bus.towards": "Mot %@",
            "time.now": "Nu",
            "sleepPopup.title": "Rödbuss gick i viloläge.",
            "sleepPopup.wakeUp": "Väck appen!",
        ]
    ]

    /// Returns localized string for key in the given language. Falls back to English if missing.
    static func string(_ key: String, language: String) -> String {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dict = strings[lang], let value = dict[key] {
            return value
        }
        return strings["English"]?[key] ?? key
    }

    /// Format string with one argument (e.g. "Buses from %@").
    static func string(_ key: String, language: String, _ arg: String) -> String {
        let template = string(key, language: language)
        return template.replacingOccurrences(of: "%@", with: arg)
    }

    /// Format string with two arguments.
    static func string(_ key: String, language: String, _ arg1: String, _ arg2: String) -> String {
        var s = string(key, language: language)
        if let r = s.range(of: "%@") { s.replaceSubrange(r, with: arg1) }
        if let r = s.range(of: "%@") { s.replaceSubrange(r, with: arg2) }
        return s
    }
}
