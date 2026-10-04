// Game text in every supported language.
//
// Every visible string is a Key. Each language is an enumerated array over Key
// with no #partial: the compiler refuses a table that misses a key, so a new
// string cannot be forgotten in one language.
//
// All texts are ours, written from Apuleius' Latin (no modern translations).
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
	Levels,
	Book,
	Settings,
	Quit,
	Footer,
	Quote,
	Lang_Name,

	// acts: label, title, the card before the act (Act I: the prologue)
	Act_1,
	Act_2,
	Act_3,
	Act_4,
	Act_Epilogue,
	Act_1_Title,
	Act_2_Title,
	Act_3_Title,
	Act_4_Title,
	Act_Epilogue_Title,
	Act_1_Card,
	Act_2_Card,
	Act_3_Card,
	Act_4_Card,
	Act_Epilogue_Card,
	Card_Continue,
	Card_Unbuilt,

	// level titles
	Level_I_1,
	Level_I_2,
	Level_I_3,
	Level_I_4,
	Level_II_1,
	Level_II_2,
	Level_II_3,
	Level_II_4,
	Level_II_5,
	Level_III_1,
	Level_III_2,
	Level_III_3,
	Level_III_4,
	Level_III_5,
	Level_IV_1,
	Level_IV_2,
	Level_IV_3,
	Level_IV_4,
	Level_IV_5,
	Level_Epilogue,

	// level select
	Levels_Title,
	Level_Unbuilt,
	Level_Locked,
	Fragments_Label,

	// fragments of the tale, one per level (in level order)
	Fragment_01,
	Fragment_02,
	Fragment_03,
	Fragment_04,
	Fragment_05,
	Fragment_06,
	Fragment_07,
	Fragment_08,
	Fragment_09,
	Fragment_10,
	Fragment_11,
	Fragment_12,
	Fragment_13,
	Fragment_14,
	Fragment_15,
	Fragment_16,
	Fragment_17,
	Fragment_18,
	Fragment_19,
	Fragment_20,
	Fragment_Found,
	Fragment_Continue,

	// the Book
	Book_Fragments,
	Book_Missing,
	Book_Achievements,
	Book_Hidden,

	// achievements: name and condition
	Achievement,
	Ach_Tale_1,
	Ach_Tale_2,
	Ach_Tale_3,
	Ach_Tale_4,
	Ach_Tale_1_Desc,
	Ach_Tale_2_Desc,
	Ach_Tale_3_Desc,
	Ach_Tale_4_Desc,
	Ach_Old_Woman,
	Ach_Old_Woman_Desc,
	Ach_Trust,
	Ach_Trust_Desc,
	Ach_Trust_Secret,
	Ach_No_Wasted_Light,
	Ach_No_Wasted_Light_Desc,
	Ach_Wedding,
	Ach_Wedding_Desc,

	// in game
	Oil,
	Lamp_Button,
	Controls,
	Controls_Dark,

	// Cupid's voice (level files refer to these by name, case-insensitive)
	V_Welcome,
	V_Rule,
	V_Lamp,
	V_Decoy,
	V_Turn,
	V_Sigil,
	V_Chamber,
	V_First_Light,
	V_Doubt,

	Hint_Move,
	Hint_Lamp,
	Hint_Turn,
	Hint_Seam,
	Hint_No_Oil,
	Hint_Hidden_Stairs,

	// endings
	End_Trust_Title,
	End_Trust,
	End_Trust_Note,
	End_Oil_Title,
	End_Oil,
	End_Exit_Title,
	End_Of_Act,
	Next,
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
	.Levels         = "Livelli",
	.Book           = "Il Libro",
	.Settings       = "Impostazioni",
	.Quit           = "Esci",
	.Footer         = "Da Apuleio, Metamorfosi IV–VI",
	.Quote          = "«Non cercare di vedere il mio volto.»\n— Apuleio, Metamorfosi V",
	.Lang_Name      = "Italiano",

	.Act_1          = "Atto I",
	.Act_2          = "Atto II",
	.Act_3          = "Atto III",
	.Act_4          = "Atto IV",
	.Act_Epilogue   = "Epilogo",
	.Act_1_Title    = "Il palazzo delle voci",
	.Act_2_Title    = "L'abbandono",
	.Act_3_Title    = "Le prove di Venere",
	.Act_4_Title    = "Il vaso di Proserpina",
	.Act_Epilogue_Title = "Il risveglio",
	.Act_1_Card     = "«Sulla rupe di un alto monte, o re, lascia la fanciulla, vestita per nozze di morte. Non sperare un genero di stirpe mortale.»\nCosì risponde Apollo. Psiche sale sola sulla rupe, e il vento la prende.",
	.Act_2_Card     = "La goccia d'olio ha svegliato il dio. Amore vola via, e il palazzo si scioglie nell'aria.\nPsiche resta sola sulla terra, a cercarlo.",
	.Act_3_Card     = "Psiche bussa alla porta di Venere. La dea ride, e le dà lavori impossibili.\nMa piccole creature hanno pietà di lei.",
	.Act_4_Card     = "L'ultima prova: scendere da Proserpina e chiederle un po' della sua bellezza, chiusa in un vaso.\nDall'Ade nessuno torna.",
	.Act_Epilogue_Card = "Psiche dorme il sonno dello Stige, come una morta.\nLontano, una finestra si apre.",
	.Card_Continue  = "Clic per continuare",
	.Card_Unbuilt   = "Questo atto è ancora in costruzione.",

	.Level_I_1      = "La rupe di Zefiro",
	.Level_I_2      = "Il palazzo invisibile",
	.Level_I_3      = "Le sorelle sulla rupe",
	.Level_I_4      = "La lampada e il rasoio",
	.Level_II_1     = "Il volo di Amore",
	.Level_II_2     = "Il fiume e Pan",
	.Level_II_3     = "La rupe delle sorelle",
	.Level_II_4     = "Il tempio di Cerere",
	.Level_II_5     = "Il tempio di Giunone",
	.Level_III_1    = "La casa di Venere",
	.Level_III_2    = "I semi",
	.Level_III_3    = "Il vello d'oro",
	.Level_III_4    = "L'acqua dello Stige",
	.Level_III_5    = "L'ordine del vaso",
	.Level_IV_1     = "La torre che parla",
	.Level_IV_2     = "Il Tenaro e l'asinaio zoppo",
	.Level_IV_3     = "Caronte e il morto nel fiume",
	.Level_IV_4     = "Cerbero e Proserpina",
	.Level_IV_5     = "Il vaso aperto",
	.Level_Epilogue = "Il risveglio e le nozze",

	.Levels_Title   = "Livelli",
	.Level_Unbuilt  = "Ancora in costruzione",
	.Level_Locked   = "Finisci prima i livelli che lo precedono",
	.Fragments_Label = "Frammenti",

	.Fragment_01    = "C'erano in una città un re e una regina, con tre figlie. Le due maggiori erano belle; la più giovane, così bella che le parole non bastavano.",
	.Fragment_02    = "Da ogni parte venivano a vederla, e la adoravano come una nuova Venere. I templi della dea restavano vuoti, gli altari freddi.",
	.Fragment_03    = "Venere chiama il figlio alato: «Fa' che la fanciulla arda d'amore per l'ultimo degli uomini, il più misero di tutti.»",
	.Fragment_04    = "Il padre, temendo l'ira degli dèi, interroga l'antico oracolo di Apollo a Mileto. Il dio risponde in versi: lo sposo è un male alato, che fa tremare anche Giove.",
	.Fragment_05    = "Mentre guarda le armi del dio, Psiche si punge con una delle sue frecce. Così, senza saperlo, si innamora di Amore.",
	.Fragment_06    = "Le fiaccole nuziali fanno fumo nero, il flauto suona un lamento. Tutta la città accompagna la sposa come a un funerale.",
	.Fragment_07    = "Un gabbiano bianco si tuffa in fondo al mare e racconta tutto a Venere: suo figlio è ferito, e ama una mortale.",
	.Fragment_08    = "Venere rimprovera il figlio con parole dure e lo chiude in una stanza della sua casa, perché non riveda la fanciulla.",
	.Fragment_09    = "Cerere e Giunone cercano di calmarla: è giovane, è innamorato, perché punirlo? Ma parlano così per paura delle sue frecce.",
	.Fragment_10    = "Mercurio grida il bando per tutte le strade: a chi riporta la fuggitiva, Venere darà sette baci.",
	.Fragment_11    = "Amore è chiuso in una stanza in fondo alla casa, lontano da tutti. La ferita della lampada guarisce piano.",
	.Fragment_12    = "Venere va a un banchetto di nozze, profumata e coronata di rose. Lascia Psiche sola, davanti al lavoro impossibile.",
	.Fragment_13    = "L'acqua nera scende da una rupe altissima, tra rocce lisce. Draghi senza sonno la custodiscono, e le acque stesse gridano: «Vattene!»",
	.Fragment_14    = "«Va' da Proserpina» dice Venere, «e chiedile un po' della sua bellezza, quanto basta per un giorno.»",
	.Fragment_15    = "Psiche capisce che la mandano a morire. Sale su un'alta torre per gettarsi di sotto: è la via più breve per l'Ade.",
	.Fragment_16    = "Non lontano c'è il Tenaro, uno spiraglio da cui respira il regno dei morti. Da lì una strada impervia scende fino alla reggia di Dite.",
	.Fragment_17    = "Caronte non fa nulla gratis. Anche tra i morti vive l'avarizia: chi muore deve portare la moneta in bocca.",
	.Fragment_18    = "Proserpina le offre un seggio morbido e un ricco banchetto. Psiche siede a terra e chiede solo pane scuro.",
	.Fragment_19    = "Amore, guarito, non sopporta più la lontananza. Fugge dall'alta finestra della sua prigione e vola da lei.",
	.Fragment_20    = "Così si compiono le nozze, e nasce una figlia che chiamano Voluttà.\nQuesta favola raccontava una vecchia a una ragazza prigioniera, nella caverna dei briganti.",
	.Fragment_Found = "Frammento del racconto",
	.Fragment_Continue = "Premi Invio per continuare",

	.Book_Fragments = "Frammenti del racconto",
	.Book_Missing   = "frammento non ancora trovato",
	.Book_Achievements = "Traguardi",
	.Book_Hidden    = "Traguardo segreto",

	.Achievement    = "Traguardo",
	.Ach_Tale_1     = "La favola · Atto I",
	.Ach_Tale_2     = "La favola · Atto II",
	.Ach_Tale_3     = "La favola · Atto III",
	.Ach_Tale_4     = "La favola · Atto IV",
	.Ach_Tale_1_Desc = "Tutti i frammenti dell'Atto I",
	.Ach_Tale_2_Desc = "Tutti i frammenti dell'Atto II",
	.Ach_Tale_3_Desc = "Tutti i frammenti dell'Atto III",
	.Ach_Tale_4_Desc = "Tutti i frammenti dell'Atto IV",
	.Ach_Old_Woman  = "La vecchia e la ragazza",
	.Ach_Old_Woman_Desc = "Tutti i venti frammenti del racconto",
	.Ach_Trust      = "Fiducia",
	.Ach_Trust_Desc = "Raggiungere Amore al buio, senza guardarlo",
	.Ach_Trust_Secret = "Un finale segreto, dopo la fine del gioco",
	.Ach_No_Wasted_Light = "Nessuna luce superflua",
	.Ach_No_Wasted_Light_Desc = "Finire un livello accendendo la lampada solo dove serve",
	.Ach_Wedding    = "Le nozze",
	.Ach_Wedding_Desc = "Finire il gioco",

	.Oil            = "Olio",
	.Lamp_Button    = "Lampada",
	.Controls       = "Clic: cammina  ·  Q / E: ruota il palazzo  ·  Spazio / tasto destro: lampada  ·  R: ricomincia  ·  Esc: pausa",
	.Controls_Dark  = "Clic: cammina  ·  Q / E: ruota il palazzo  ·  R: ricomincia  ·  Esc: pausa",

	.V_Welcome      = "Benvenuta, Psiche. Questa casa è tua, e ogni voce che senti è qui per servirti.",
	.V_Rule         = "Non cercare di vedere. Al buio, ciò che sembra unito è unito.",
	.V_Lamp         = "Le tue sorelle ti hanno dato una lampada. Accendila, se devi… ma ciò che la luce mostra, la luce lo divide.",
	.V_Decoy        = "Solo vento, qui. Il palazzo custodisce altrove i suoi segreti.",
	.V_Turn         = "Il palazzo ha molti volti. Giralo, e cerca quello che ti accoglie.",
	.V_Sigil        = "Hai trovato il sigillo. Ora spegni la lampada: da me si arriva solo al buio.",
	.V_Chamber      = "Sono qui. Non guardarmi: se vedi il mio volto, mi perderai.",
	.V_First_Light  = "La luce rivela… e divide.",
	.V_Doubt        = "Dorme. Ti tornano in mente le parole delle sorelle: e se fosse un mostro? La lampada è nella tua mano.",

	.Hint_Move      = "Clicca sul palazzo per camminare",
	.Hint_Lamp      = "Spazio o tasto destro: accendi o spegni la lampada",
	.Hint_Turn      = "Q / E o le frecce: ruota il palazzo",
	.Hint_Seam      = "Alla luce, il passaggio non c'è",
	.Hint_No_Oil    = "L'olio è finito. Premi R per ricominciare.",
	.Hint_Hidden_Stairs = "Al buio, una scala che non vedi non porta da nessuna parte",

	.End_Trust_Title = "Fiducia",
	.End_Trust      = "Resti al buio, accanto a lui.\nNon conosci il suo volto, ma conosci il suo respiro.",
	.End_Trust_Note = "Un finale segreto, fuori dal racconto di Apuleio",
	.End_Oil_Title  = "La goccia d'olio",
	.End_Oil        = "La luce ti mostra il più bello degli dèi.\nUna goccia d'olio bollente cade sulla sua spalla:\nAmore si sveglia, e vola via. Il palazzo non c'è più.",
	.End_Exit_Title = "Il passaggio è aperto",
	.End_Of_Act     = "Fine dell'",
	.Next           = "Continua",
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
	.Levels         = "Levels",
	.Book           = "The Book",
	.Settings       = "Settings",
	.Quit           = "Quit",
	.Footer         = "After Apuleius, Metamorphoses IV–VI",
	.Quote          = "“Do not seek to see my face.”\n— Apuleius, Metamorphoses V",
	.Lang_Name      = "English",

	.Act_1          = "Act I",
	.Act_2          = "Act II",
	.Act_3          = "Act III",
	.Act_4          = "Act IV",
	.Act_Epilogue   = "Epilogue",
	.Act_1_Title    = "The Palace of Voices",
	.Act_2_Title    = "Abandoned",
	.Act_3_Title    = "The Trials of Venus",
	.Act_4_Title    = "Proserpina's Box",
	.Act_Epilogue_Title = "The Awakening",
	.Act_1_Card     = "“On the crag of a high mountain, king, leave the girl, dressed for a wedding of death. Hope for no son-in-law of mortal birth.”\nSo Apollo answers. Psyche climbs the crag alone, and the wind takes her.",
	.Act_2_Card     = "The drop of oil has woken the god. Cupid flies away, and the palace melts into the air.\nPsyche is left alone on the earth, to search for him.",
	.Act_3_Card     = "Psyche knocks at the door of Venus. The goddess laughs and sets her impossible tasks.\nBut small creatures take pity on her.",
	.Act_4_Card     = "The last trial: go down to Proserpina and ask her for a little of her beauty, shut in a box.\nNo one comes back from Hades.",
	.Act_Epilogue_Card = "Psyche sleeps the sleep of the Styx, like one dead.\nFar away, a window opens.",
	.Card_Continue  = "Click to continue",
	.Card_Unbuilt   = "This act is still being built.",

	.Level_I_1      = "Zephyr's Crag",
	.Level_I_2      = "The Invisible Palace",
	.Level_I_3      = "The Sisters on the Crag",
	.Level_I_4      = "The Lamp and the Razor",
	.Level_II_1     = "Cupid's Flight",
	.Level_II_2     = "The River and Pan",
	.Level_II_3     = "The Sisters' Crag",
	.Level_II_4     = "The Temple of Ceres",
	.Level_II_5     = "The Temple of Juno",
	.Level_III_1    = "The House of Venus",
	.Level_III_2    = "The Seeds",
	.Level_III_3    = "The Golden Fleece",
	.Level_III_4    = "The Water of the Styx",
	.Level_III_5    = "The Order of the Box",
	.Level_IV_1     = "The Speaking Tower",
	.Level_IV_2     = "Taenarus and the Lame Driver",
	.Level_IV_3     = "Charon and the Dead Man",
	.Level_IV_4     = "Cerberus and Proserpina",
	.Level_IV_5     = "The Open Box",
	.Level_Epilogue = "The Awakening and the Wedding",

	.Levels_Title   = "Levels",
	.Level_Unbuilt  = "Still being built",
	.Level_Locked   = "Finish the levels before it first",
	.Fragments_Label = "Fragments",

	.Fragment_01    = "In a certain city there were a king and a queen, with three daughters. The two elder were beautiful; the youngest so beautiful that words fell short.",
	.Fragment_02    = "People came from everywhere to see her, and worshipped her as a new Venus. The goddess's temples stood empty, her altars cold.",
	.Fragment_03    = "Venus calls her winged son: “Make the girl burn with love for the lowest of men, the most wretched of all.”",
	.Fragment_04    = "Her father, fearing the anger of the gods, consults the ancient oracle of Apollo at Miletus. The god answers in verse: the bridegroom is a winged evil that makes even Jupiter tremble.",
	.Fragment_05    = "Looking at the god's weapons, Psyche pricks herself on one of his arrows. So, without knowing it, she falls in love with Love.",
	.Fragment_06    = "The wedding torches burn with black smoke, the flute plays a lament. The whole city follows the bride as if to a funeral.",
	.Fragment_07    = "A white gull dives to the bottom of the sea and tells Venus everything: her son is wounded, and he loves a mortal.",
	.Fragment_08    = "Venus scolds her son with harsh words and locks him in a room of her house, so that he will not see the girl again.",
	.Fragment_09    = "Ceres and Juno try to calm her: he is young, he is in love, why punish him? But they speak so for fear of his arrows.",
	.Fragment_10    = "Mercury cries the proclamation through every street: whoever brings back the runaway will have seven kisses from Venus.",
	.Fragment_11    = "Cupid is shut in a room at the back of the house, far from everyone. The wound of the lamp heals slowly.",
	.Fragment_12    = "Venus goes off to a wedding feast, perfumed and crowned with roses. She leaves Psyche alone with the impossible task.",
	.Fragment_13    = "Black water falls from a towering crag, between smooth rocks. Sleepless dragons guard it, and the waters themselves cry out: “Go away!”",
	.Fragment_14    = "“Go to Proserpina,” says Venus, “and ask her for a little of her beauty, enough for a single day.”",
	.Fragment_15    = "Psyche understands she is being sent to die. She climbs a high tower to throw herself down: the shortest road to Hades.",
	.Fragment_16    = "Not far away lies Taenarus, a vent through which the kingdom of the dead breathes. From there a rough road leads down to the palace of Dis.",
	.Fragment_17    = "Charon does nothing for free. Even among the dead greed lives on: whoever dies must carry the coin in his mouth.",
	.Fragment_18    = "Proserpina offers her a soft seat and a rich feast. Psyche sits on the ground and asks only for coarse bread.",
	.Fragment_19    = "Cupid, healed, can bear the separation no longer. He escapes through the high window of his prison and flies to her.",
	.Fragment_20    = "So the wedding is made, and a daughter is born whom they call Pleasure.\nThis was the tale an old woman told a captive girl, in the robbers' cave.",
	.Fragment_Found = "Fragment of the Tale",
	.Fragment_Continue = "Press Enter to continue",

	.Book_Fragments = "Fragments of the Tale",
	.Book_Missing   = "fragment not found yet",
	.Book_Achievements = "Achievements",
	.Book_Hidden    = "Secret achievement",

	.Achievement    = "Achievement",
	.Ach_Tale_1     = "The Tale · Act I",
	.Ach_Tale_2     = "The Tale · Act II",
	.Ach_Tale_3     = "The Tale · Act III",
	.Ach_Tale_4     = "The Tale · Act IV",
	.Ach_Tale_1_Desc = "Every fragment of Act I",
	.Ach_Tale_2_Desc = "Every fragment of Act II",
	.Ach_Tale_3_Desc = "Every fragment of Act III",
	.Ach_Tale_4_Desc = "Every fragment of Act IV",
	.Ach_Old_Woman  = "The Old Woman and the Girl",
	.Ach_Old_Woman_Desc = "All twenty fragments of the tale",
	.Ach_Trust      = "Trust",
	.Ach_Trust_Desc = "Reach Cupid in the dark, without looking at him",
	.Ach_Trust_Secret = "A secret ending, after the end of the game",
	.Ach_No_Wasted_Light = "No Wasted Light",
	.Ach_No_Wasted_Light_Desc = "Finish a level lighting the lamp only where it is needed",
	.Ach_Wedding    = "The Wedding",
	.Ach_Wedding_Desc = "Finish the game",

	.Oil            = "Oil",
	.Lamp_Button    = "Lamp",
	.Controls       = "Click: walk  ·  Q / E: turn the palace  ·  Space / right click: lamp  ·  R: restart  ·  Esc: pause",
	.Controls_Dark  = "Click: walk  ·  Q / E: turn the palace  ·  R: restart  ·  Esc: pause",

	.V_Welcome      = "Welcome, Psyche. This house is yours, and every voice you hear is here to serve you.",
	.V_Rule         = "Do not try to see. In the dark, what seems joined is joined.",
	.V_Lamp         = "Your sisters gave you a lamp. Light it if you must… but what the light reveals, the light divides.",
	.V_Decoy        = "Only wind, here. The palace keeps its secrets elsewhere.",
	.V_Turn         = "The palace has many faces. Turn it, and look for the one that welcomes you.",
	.V_Sigil        = "You found the seal. Now put out the lamp: only the dark leads to me.",
	.V_Chamber      = "I am here. Do not look at me: if you see my face, you will lose me.",
	.V_First_Light  = "The light reveals… and divides.",
	.V_Doubt        = "He sleeps. Your sisters' words come back to you: what if he is a monster? The lamp is in your hand.",

	.Hint_Move      = "Click on the palace to walk",
	.Hint_Lamp      = "Space or right click: light or put out the lamp",
	.Hint_Turn      = "Q / E or the arrows: turn the palace",
	.Hint_Seam      = "In the light, there is no passage",
	.Hint_No_Oil    = "The oil is gone. Press R to start again.",
	.Hint_Hidden_Stairs = "In the dark, stairs you cannot see lead nowhere",

	.End_Trust_Title = "Trust",
	.End_Trust      = "You stay in the dark, beside him.\nYou do not know his face, but you know his breath.",
	.End_Trust_Note = "A secret ending, outside Apuleius' tale",
	.End_Oil_Title  = "The drop of oil",
	.End_Oil        = "The light shows you the fairest of the gods.\nA drop of burning oil falls on his shoulder:\nCupid wakes, and flies away. The palace is gone.",
	.End_Exit_Title = "The way is open",
	.End_Of_Act     = "End of ",
	.Next           = "Continue",
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
