// Game text in every supported language.
//
// Every visible string is a Key. Each language is an enumerated array over Key
// with no #partial: the compiler refuses a table that misses a key, so a new
// string cannot be forgotten in one language.
package i18n

import "core:reflect"
import "core:strings"

Language :: enum u8 {
	Italian,
	English,
}

LANGUAGE_CODE := [Language]string {
	.Italian = "it",
	.English = "en",
}

Key :: enum u16 {
	Title,
	Subtitle,
	Play,
	Settings,
	Quit,
	Footer,
	Quote,
	Lang_Name,

	// in game
	Level_1,
	Oil,
	Lamp_Button,
	Controls,

	// Cupid's voice (level files refer to these by name, case-insensitive)
	V_Welcome,
	V_Rule,
	V_Lamp,
	V_Decoy,
	V_Turn,
	V_Sigil,
	V_Chamber,
	V_First_Light,

	Hint_Move,
	Hint_Lamp,
	Hint_Turn,
	Hint_Seam,
	Hint_No_Oil,
	Hint_Hidden_Stairs,

	// endings
	End_Good_Title,
	End_Good,
	End_Bad_Title,
	End_Bad,
	End_Note,
	Retry,
	Menu,

	// pause
	Pause_Title,
	Resume,
	Restart,

	// settings
	Set_Title,
	Set_General,
	Set_Video,
	Set_Audio,
	Set_Language,
	Set_Display,
	Set_Windowed,
	Set_Fullscreen,
	Set_Resolution,
	Set_Vsync,
	Set_Fps,
	Set_Msaa,
	Set_Restart_Note,
	Set_Native,
	Set_Debug,
	Set_Master,
	Set_Music,
	Set_Sfx,
	Set_On,
	Set_Off,
	Set_Unlimited,
	Back,
}

@(private)
current: Language = .Italian

set_language :: proc(l: Language) {
	current = l
}

language :: proc() -> Language {
	return current
}

tr :: proc(k: Key) -> string {
	return TABLES[current][k]
}

tr_in :: proc(l: Language, k: Key) -> string {
	return TABLES[l][k]
}

// Key from its enum name, ignoring case ("v_rule" -> .V_Rule).
key_from_name :: proc(name: string) -> (k: Key, ok: bool) {
	for field, i in reflect.enum_field_names(Key) {
		if strings.equal_fold(field, name) {
			return Key(reflect.enum_field_values(Key)[i]), true
		}
	}
	return {}, false
}

// Language from a locale string such as "it_IT.UTF-8"; English otherwise.
language_from_locale :: proc(locale: string) -> Language {
	for code, l in LANGUAGE_CODE {
		if strings.has_prefix(locale, code) {
			return l
		}
	}
	return .English
}

TABLES := [Language]^[Key]string {
	.Italian = &IT,
	.English = &EN,
}

IT := [Key]string {
	.Title          = "LA PROVA DI PSICHE",
	.Subtitle       = "Amore e Psiche · un rompicapo sul vedere e sul fidarsi",
	.Play           = "Entra nel palazzo",
	.Settings       = "Impostazioni",
	.Quit           = "Esci",
	.Footer         = "Livello I",
	.Quote          = "«Non cercare di vedere il mio volto.»\n— Apuleio, Metamorfosi V",
	.Lang_Name      = "Italiano",

	.Level_1        = "I · La casa delle voci",
	.Oil            = "Olio",
	.Lamp_Button    = "Lampada",
	.Controls       = "Clic: cammina  ·  Q / E: ruota il palazzo  ·  Spazio / tasto destro: lampada  ·  R: ricomincia  ·  Esc: pausa",

	.V_Welcome      = "Benvenuta, Psiche. Questa casa è tua, e ogni voce che senti è qui per servirti.",
	.V_Rule         = "Non cercare di vedere. Al buio, ciò che sembra unito è unito.",
	.V_Lamp         = "Le tue sorelle ti hanno dato una lampada. Accendila, se devi… ma ciò che la luce mostra, la luce lo divide.",
	.V_Decoy        = "Solo vento, qui. Il palazzo custodisce altrove i suoi segreti.",
	.V_Turn         = "Il palazzo ha molti volti. Giralo, e cerca quello che ti accoglie.",
	.V_Sigil        = "Hai trovato il sigillo. Ora spegni la lampada: da me si arriva solo al buio.",
	.V_Chamber      = "Sono qui. Non guardarmi: se vedi il mio volto, mi perderai.",
	.V_First_Light  = "La luce rivela… e divide.",

	.Hint_Move      = "Clicca sul palazzo per camminare",
	.Hint_Lamp      = "Spazio o tasto destro: accendi o spegni la lampada",
	.Hint_Turn      = "Q / E o le frecce: ruota il palazzo",
	.Hint_Seam      = "Alla luce, il passaggio non c'è",
	.Hint_No_Oil    = "L'olio è finito. Premi R per ricominciare.",
	.Hint_Hidden_Stairs = "Al buio, una scala che non vedi non porta da nessuna parte",

	.End_Good_Title = "Fiducia",
	.End_Good       = "Resti al buio, accanto a lui.\nNon conosci il suo volto, ma conosci il suo respiro.",
	.End_Bad_Title  = "La goccia d'olio",
	.End_Bad        = "La luce ti mostra il più bello degli dèi.\nUna goccia d'olio bollente cade sulla sua spalla:\nAmore si sveglia, e vola via. Il palazzo non c'è più.",
	.End_Note       = "Fine del livello · grazie per aver giocato",
	.Retry          = "Ricomincia",
	.Menu           = "Menu",

	.Pause_Title    = "Pausa",
	.Resume         = "Riprendi",
	.Restart        = "Ricomincia il livello",

	.Set_Title      = "Impostazioni",
	.Set_General    = "Generale",
	.Set_Video      = "Video",
	.Set_Audio      = "Audio",
	.Set_Language   = "Lingua",
	.Set_Display    = "Modalità",
	.Set_Windowed   = "Finestra",
	.Set_Fullscreen = "Schermo intero",
	.Set_Resolution = "Risoluzione",
	.Set_Vsync      = "Sincronia verticale",
	.Set_Fps        = "Limite FPS",
	.Set_Msaa       = "Antialiasing",
	.Set_Restart_Note = "(al prossimo avvio)",
	.Set_Native     = "nativa",
	.Set_Debug      = "Debug (FPS) · F3",
	.Set_Master     = "Volume generale",
	.Set_Music      = "Musica",
	.Set_Sfx        = "Effetti",
	.Set_On         = "Sì",
	.Set_Off        = "No",
	.Set_Unlimited  = "Nessuno",
	.Back           = "Indietro",
}

EN := [Key]string {
	.Title          = "THE TRIAL OF PSYCHE",
	.Subtitle       = "Cupid and Psyche · a puzzle about seeing and trusting",
	.Play           = "Enter the palace",
	.Settings       = "Settings",
	.Quit           = "Quit",
	.Footer         = "Level I",
	.Quote          = "“Do not seek to see my face.”\n— Apuleius, Metamorphoses V",
	.Lang_Name      = "English",

	.Level_1        = "I · The House of Voices",
	.Oil            = "Oil",
	.Lamp_Button    = "Lamp",
	.Controls       = "Click: walk  ·  Q / E: turn the palace  ·  Space / right click: lamp  ·  R: restart  ·  Esc: pause",

	.V_Welcome      = "Welcome, Psyche. This house is yours, and every voice you hear is here to serve you.",
	.V_Rule         = "Do not try to see. In the dark, what seems joined is joined.",
	.V_Lamp         = "Your sisters gave you a lamp. Light it if you must… but what the light reveals, the light divides.",
	.V_Decoy        = "Only wind, here. The palace keeps its secrets elsewhere.",
	.V_Turn         = "The palace has many faces. Turn it, and look for the one that welcomes you.",
	.V_Sigil        = "You found the seal. Now put out the lamp: only the dark leads to me.",
	.V_Chamber      = "I am here. Do not look at me: if you see my face, you will lose me.",
	.V_First_Light  = "The light reveals… and divides.",

	.Hint_Move      = "Click on the palace to walk",
	.Hint_Lamp      = "Space or right click: light or put out the lamp",
	.Hint_Turn      = "Q / E or the arrows: turn the palace",
	.Hint_Seam      = "In the light, there is no passage",
	.Hint_No_Oil    = "The oil is gone. Press R to start again.",
	.Hint_Hidden_Stairs = "In the dark, stairs you cannot see lead nowhere",

	.End_Good_Title = "Trust",
	.End_Good       = "You stay in the dark, beside him.\nYou do not know his face, but you know his breath.",
	.End_Bad_Title  = "The drop of oil",
	.End_Bad        = "The light shows you the fairest of the gods.\nA drop of burning oil falls on his shoulder:\nLove wakes, and flies away. The palace is gone.",
	.End_Note       = "End of the level · thank you for playing",
	.Retry          = "Play again",
	.Menu           = "Menu",

	.Pause_Title    = "Paused",
	.Resume         = "Resume",
	.Restart        = "Restart the level",

	.Set_Title      = "Settings",
	.Set_General    = "General",
	.Set_Video      = "Video",
	.Set_Audio      = "Audio",
	.Set_Language   = "Language",
	.Set_Display    = "Display mode",
	.Set_Windowed   = "Windowed",
	.Set_Fullscreen = "Fullscreen",
	.Set_Resolution = "Resolution",
	.Set_Vsync      = "V-Sync",
	.Set_Fps        = "Frame limit",
	.Set_Msaa       = "Anti-aliasing",
	.Set_Restart_Note = "(after restart)",
	.Set_Native     = "native",
	.Set_Debug      = "Debug (FPS) · F3",
	.Set_Master     = "Master volume",
	.Set_Music      = "Music",
	.Set_Sfx        = "Effects",
	.Set_On         = "On",
	.Set_Off        = "Off",
	.Set_Unlimited  = "Unlimited",
	.Back           = "Back",
}
