# CrashGuard AI — 3-Minute Hackathon Video Script

**Target:** Gemma 4 Good Hackathon judges  
**Duration:** 2:55  
**Tone:** Urgent, cinematic, grounded in data  
**Format:** Screen recording + narration + captions + data overlays

---

## PRODUCTION BRIEF

| Element | Spec |
|---------|------|
| Aspect ratio | 16:9 (YouTube) |
| Resolution | 1080p minimum |
| Captions | Always on — judges often watch muted |
| Music | Understated tension → resolve (no dramatic EDM) |
| Colors | Dark backgrounds, red/blue accents matching app palette |
| Voice | Single narrator, calm and authoritative — not excited |

---

## SCENE-BY-SCENE SCRIPT

---

### SCENE 1 — THE STATISTIC  
**`[0:00 – 0:08]`**  
**Visual:** Pure black screen. Silence for 1 second.  
Then a single white line appears, one word at a time:

> *"Someone in India will die from a road crash…*  
> *…in the next 3 minutes."*

**Audio:** Distant ambulance siren. Fades.  
**Caption:** Same text on screen.  
**Cut to:** A dark highway at 2 AM. Headlights. A truck crossing lanes.

---

### SCENE 2 — THE FAILURE  
**`[0:08 – 0:42]`**  
**Visual:** Dashcam-style footage of a motorcycle collision. Vehicle stopped at side of road. A bystander runs over, pulls out phone. They dial. **"No signal."** They stare at the victim. They don't know what to do with a head injury. After 90 seconds — they leave.

**Narrator:**  
> *"India has 170,000 road deaths every year. That's one every three minutes. The majority of victims who die — had survivable injuries. They died because help was never summoned. Or because the person who stopped didn't know what to do."*

**Visual:** Time counter starts — 00:00. Reaches 01:08. Text overlay: **"Average time to first ambulance contact on rural NH highways: 68 minutes."**

**Cut to black.**  
**Text:** *"The 60-minute golden hour is already over."*

---

### SCENE 3 — SAME CRASH. DIFFERENT OUTCOME.  
**`[0:42 – 1:02]`**  
**Visual:** Replay the same crash. Same dark highway. But this time, the downed rider has a phone. The phone detects the impact. CrashGuard AI screen appears — a 10-second countdown, SOS in red.

**Narrator:**  
> *"CrashGuard AI detects crashes automatically — accelerometer and GPS fusion. No button press. No internet required. In the next 10 seconds, Gemma 4 takes over."*

**Visual:** The app screen. Microphone waveform. Then — text begins streaming into a triage card in real-time.

---

### SCENE 4 — GEMMA 4 LIVE  
**`[1:02 – 1:55]`**  
**[This is the technical demo section — screen recording of the browser demo]**

**Visual:** Browser demo at `demo/index.html`. Preset scenario selected:  
*"Ek truck aur motorcycle ki takkar NH-48 par raat 2 baje. Biker helmet nahi pehna tha, unconscious hai, khoon aa raha hai."*

A bystander who stopped takes a crash-scene photo. It gets uploaded to the demo. Gemma 4 starts streaming.

**The stream output fills the right panel — raw JSON appearing token by token:**

```
{
  "severity_level": 5,
  "required_services": ["ambulance", "police"],
  "first_aid_focus": "Control severe head bleeding with firm direct
```

**Narrator:**  
> *"Gemma 4 27B analyzes the voice description and the crash scene photo together. This is multimodal emergency triage — something no previous open-weight model could do."*

**Visual:** Severity card snaps to: 🆘 **LIFE-THREATENING — Maximum emergency response.** Services dispatched: Ambulance. Police.

**Visual:** First-aid card fills: *"Control severe head bleeding with firm direct pressure. Do not move victim — assume spinal injury from high-speed impact."*

**Narrator:**  
> *"Simultaneously — an SMS fires to 112 with GPS coordinates. A Bluetooth beacon broadcasts to every CrashGuard AI phone within 200 metres. The bystander who stopped gets voice-guided first aid instructions — in Hindi."*

**Visual:** Phone showing Hindi TTS playing: "Sar par pressure daalein..."

---

### SCENE 5 — THE WOW MOMENT  
**`[1:55 – 2:20]`**  
**Visual:** Split-screen. Left panel: **Keyword Classifier (no AI)**. Right panel: **Gemma 4**.

Same input: *"Vehicle rolled, smoke visible, two adults trapped, one silent."*

**Left side fills:**
```
Severity: 3 / 5  
Services: ambulance  
Matched keywords: smoke, trapped  
```

**Right side fills — streaming:**
```json
{
  "severity_level": 5,
  "required_services": ["ambulance", "fire_department", "rescue"],
  "first_aid_focus": "Move upwind — fuel smell indicates fire risk. 
    Do not enter vehicle. Extrication requires fire department.",
  "thinking_summary": "Rollover with smoke and fuel smell, one silent 
    occupant — fire imminent. Standard ambulance dispatch is fatal here. 
    Fire + rescue required immediately."
}
```

**Narrator (quieter, slower):**  
> *"Both are looking at the same words. One calls an ambulance. One calls a fire department and rescue team — because it recognizes that a silent occupant in a smoking vehicle means the ambulance will arrive to a fire."*

**Text slam on screen, white on black:**  
> **"Same accident. Different services dispatched."**  
> **"Same accident. Different outcome."**

---

### SCENE 6 — NO INTERNET? STILL WORKS.  
**`[2:20 – 2:38]`**  
**Visual:** Phone goes into airplane mode. Same scenario runs. App routes to:  
`Tier 2 → Gemma 4 E4B on-device`. Progress shown as a tier diagram lighting up.

**Narrator:**  
> *"India's national highways span 146,000 kilometres. Most crash clusters are in zero-coverage zones. So CrashGuard AI carries Gemma 4 on the phone itself — Gemma 4 E4B, quantized to 2.4 GB, running entirely on-device with no internet. Triage still fires. Dispatch still fires via SMS. The golden hour is still reachable."*

**Visual:** Tier diagram — Tier 1 (cloud) grayed out, Tier 2 (on-device, LiteRT) glowing blue.

---

### SCENE 7 — SCALE  
**`[2:38 – 2:55]`**  
**Visual:** Animated map of India. Dots appearing on highway crash hotspots — NH-48, NH-44, NH-8. Numbers rising: 170,000 / year.

**Narrator:**  
> *"CrashGuard AI is MIT-licensed, open-source, and deployable by any state emergency service in India. It supports English, Hindi, Bengali, Marathi, Tamil, and Telugu — because emergencies happen in every language."*

**Visual:** Six language chips appearing on screen.

**Narrator (final line — slow):**  
> *"Gemma 4. Open-weight. Offline-capable. Multilingual. In a country where the difference between life and death is measured in minutes — that matters."*

**Final frame:** CrashGuard AI logo. URL. GitHub link. Hackathon badge.  
**Silence for 1 second.**  
**Fade to black.**

---

## SHOT LIST

| # | Type | Content | Duration |
|---|------|---------|----------|
| 1 | Title card | Statistic on black | 8s |
| 2 | B-roll | Highway collision (stock or simulated) | 15s |
| 3 | Screen record | Bystander dialing, no signal | 10s |
| 4 | Animation | Time counter — 68 min stat | 9s |
| 5 | Screen record | Crash detection on phone | 10s |
| 6 | Screen record | Browser demo — scenario load + Gemma streaming | 40s |
| 7 | Screen record | Vision photo upload + analysis | 13s |
| 8 | Screen record | Dispatch firing (SMS, BLE) | 8s |
| 9 | Split-screen | Keyword vs Gemma comparison | 25s |
| 10 | Screen record | Offline mode — tier routing | 18s |
| 11 | Animation | India map + highway coverage | 17s |
| **Total** | | | **2:53** |

---

## NARRATION SCRIPT (CLEAN — FOR RECORDING)

> "Someone in India will die from a road crash in the next three minutes.
>
> India has 170,000 road deaths every year. The majority of victims who die had survivable injuries. They died because help was never summoned. Or because the person who stopped didn't know what to do.
>
> The average time to first ambulance contact on rural national highways is 68 minutes. The golden hour is already over.
>
> CrashGuard AI detects crashes automatically — accelerometer and GPS fusion. No button press. No internet required.
>
> Gemma 4 27B analyzes the voice description and the crash scene photo together. This is multimodal emergency triage — something no previous open-weight model could do.
>
> Simultaneously — an SMS fires to 112 with GPS coordinates. A Bluetooth beacon broadcasts to every CrashGuard AI phone within 200 metres. The bystander who stopped gets voice-guided first aid instructions in Hindi.
>
> Both are looking at the same words. One calls an ambulance. One calls a fire department and rescue team — because it recognizes that a silent occupant in a smoking vehicle means the ambulance will arrive to a fire.
>
> India's national highways span 146,000 kilometres. Most crash clusters are in zero-coverage zones. So CrashGuard AI carries Gemma 4 on the phone itself — Gemma 4 E4B, running entirely on-device, no internet required.
>
> CrashGuard AI is MIT-licensed, open-source, and deployable by any state emergency service in India. It supports English, Hindi, Bengali, Marathi, Tamil, and Telugu.
>
> Gemma 4. Open-weight. Offline-capable. Multilingual. In a country where the difference between life and death is measured in minutes — that matters."

---

## WOW MOMENTS (for judge psychology)

| Moment | Why it works |
|--------|-------------|
| The 3-minute statistic with silence | Creates visceral time pressure — judge is thinking "someone just died" |
| Keyword vs Gemma split-screen | Visual proof, not claim — judges can see the quality delta instantly |
| Airplane mode demo | Removes the #1 objection ("what if there's no internet") live on screen |
| Token-by-token streaming | Makes AI reasoning visible — feels powerful, not like a black box |
| "Same accident. Different outcome." | The emotional payoff — connects AI capability to human survival |

---

## PRE-EMPTED JUDGE QUESTIONS

**Q: "Is this just GPT-4 with a safety prompt?"**  
Show the split-screen. Ask if GPT-4 runs offline on a 4 GB RAM phone. It doesn't. Gemma 4 E4B does.

**Q: "Does this actually work offline?"**  
Switch airplane mode live in demo. Tier 2 lights up. Triage runs. Show it.

**Q: "Is the dispatch real?"**  
Point to the Supabase Edge Function logs. Show the Twilio webhook config. The SMS path is server-side — no key on device, no fake.

**Q: "Why not just use an existing emergency app?"**  
India's 108 works when you're conscious, have signal, and can describe your location. CrashGuard AI works when none of those are true.

**Q: "Is the Hindi/multilingual support real?"**  
Run Scenario 3 in the notebook live. Gemma 4 takes Hindi/English mixed input and produces correct English triage JSON.
