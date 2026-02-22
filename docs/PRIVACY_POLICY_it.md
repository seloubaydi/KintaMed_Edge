# Informativa sulla Privacy per KintaMed Edge 🛡️

**Ultimo aggiornamento: 23 gennaio 2026**

KintaMed Edge si impegna a proteggere la privacy e la sicurezza dei dati dei pazienti gestiti dagli Operatori Sanitari di Comunità (OSC). Questa Informativa sulla Privacy spiega la nostra filosofia dei dati "Zero-Cloud" e come garantiamo l'assoluta riservatezza sul campo.

---

## 1. Filosofia dei dati Zero-Cloud
KintaMed Edge è un'applicazione **primariamente offline (offline-first)**. **Non raccogliamo, trasmettiamo né memorizziamo alcun dato su server esterni, fornitori di servizi cloud o database di terze parti.**

Tutto ciò che inserisci nell'app rimane sul dispositivo fisico in cui l'app è installata.

## 2. Dati che elaboriamo localmente
Per fornire supporto alle decisioni cliniche, l'app elabora i seguenti dati esclusivamente sul tuo dispositivo:
- **Dati anagrafici del paziente**: Nome, età, genere, data di nascita.
- **Dati clinici**: Segni vitali (PA, SpO2, frequenza cardiaca, ecc.), sintomi e anamnesi medica.
- **Media clinici**: Foto di ferite, eruzioni cutanee o immagini diagnostiche.
- **Registrazioni vocali**: Elaborazione audio temporanea per la conversione da voce a testo.

## 3. Sicurezza dei dati e crittografia
Tutti i dati memorizzati sul dispositivo sono protetti da **SQLCipher**, che fornisce una crittografia di livello militare (AES-256). Ciò garantisce che anche se il dispositivo fisico viene smarrito o rubato, non sia possibile accedere alle informazioni del paziente senza le credenziali autorizzate dell'applicazione.

## 4. Autorizzazioni richieste
L'app richiede autorizzazioni specifiche per funzionare sul campo:
- **Fotocamera**: Per acquisire immagini cliniche per l'analisi dell'IA.
- **Microfoni**: Per consentire la registrazione dei sintomi in vivavoce.
- **Archiviazione/File System**: Per memorizzare i pesi del modello IA MedGemma (~3 GB) e il database locale crittografato.

## 5. Accesso di terze parti
Non esiste **alcun accesso di terze parti** ai tuoi dati. Poiché l'app non si connette a Internet per le sue funzioni principali, nessun dato può essere condiviso con inserzionisti, fornitori di analisi o agenzie governative.

## 6. Conservazione dei dati
I dati vengono conservati sul tuo dispositivo fino a quando non elimini manualmente una valutazione o cancelli i dati dell'app. Gli utenti sono responsabili dell'esecuzione di periodiche eliminazioni dei dati in conformità con i protocolli della propria organizzazione sanitaria locale.

## 7. Contatti
Per domande riguardanti l'implementazione tecnica della presente informativa sulla privacy, si prega di contattare il team di sviluppo presso il nostro repository.

---
**Nota**: Utilizzando KintaMed Edge, l'utente riconosce di essere responsabile della sicurezza fisica del dispositivo e della riservatezza dei dati del paziente visualizzati sullo schermo.
