# LFP Dashboard

![LFP Dashboard](logo.png)

An interactive MATLAB app for exploring and comparing pallidal local field potential (LFP) recordings from Medtronic Percept™ (BrainSense™) DBS devices. It loads the JSON session files exported from the clinician programmer and brings the recording modalities together in one window: Timeline, Events, Survey (frequency and time domain), and Streaming. You can then compare any two or more sessions to see how neural activity changes with therapy.

The whole app is a single file, `LFPDashboard.m`, and uses **base MATLAB only**. No Signal Processing or Statistics toolbox is required: filtering, Hilbert transform, Welch PSD, spectrograms, percentiles, FOOOF-style fitting, IRASA and every statistical test are implemented in the file.

> **Research use only.** This tool is intended for research and exploratory analysis. It is not a medical device and must not be used to make clinical decisions.

---

## Contents

- [Minimum system requirements](#minimum-system-requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Input data](#input-data)
- [Session selection and multi-session comparison](#session-selection-and-multi-session-comparison)
- [Tabs and features](#tabs-and-features)
- [Severity scores and annotations](#severity-scores-and-annotations)
- [Global settings](#global-settings)
- [Exporting results](#exporting-results)
- [Methods reference](#methods-reference)
- [Conventions](#conventions)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

---

## Minimum system requirements

| Item | Requirement |
|---|---|
| MATLAB | **R2021a or newer** (uses `uigridlayout` scrolling, edit-field placeholders, the `turbo` colormap, `boxchart`, `exportgraphics`, and custom data tips) |
| Toolboxes | **None** (base MATLAB only) |
| Operating system | Any platform supported by your MATLAB release (Windows, macOS, Linux) |
| Memory | 8 GB RAM recommended; more if you load many sessions with long streaming recordings |
| Display | 1360 × 840 or larger recommended. Smaller windows work, and scroll bars appear automatically. |
| Optional | R2021b or newer for gap filling in *Timeline 3D* (`fillmissing` with `'MaxGap'`). Older releases skip the fill without error. |

---

## Installation

1. Save `LFPDashboard.m` to a folder of your choice.
2. In MATLAB, add that folder to the path (or `cd` into it):
   ```matlab
   addpath('path/to/folder')
   ```
3. Launch the app:
   ```matlab
   LFPDashboard
   ```

No compilation or additional files are needed.

---

## Quick start

1. Click **Load JSON files...** and select one or more Percept session exports. You can load files in several batches; duplicates are skipped.
2. In the **Sessions** table on the left, tick the sessions to include. Every tab works on the ticked sessions only.
3. Check that the **Time zone** matches where the patient lives. Device timestamps are UTC, and this setting controls hour-of-day and daily calculations.
4. Open any tab and use its controls. Most plots update automatically; analyses that take longer have their own button (**Analyze**, **Compare**, **Fit**, **Run**, **Plot**).
5. Use **Export current tab as PNG...** to save every plot in the open tab at 300 dpi.

---

## Input data

### Supported files

Medtronic Percept PC / RC session JSON exports. Field names are matched case-insensitively, so minor differences between firmware versions are tolerated.

| JSON block | Used for |
|---|---|
| `DiagnosticData.LFPTrendLogs` | Timeline (chronic 10-min LFP power and stimulation amplitude) |
| `DiagnosticData.LfpFrequencySnapshotEvents` | Patient-marked events and their snapshot spectra |
| `LFPMontage` | BrainSense Survey spectra per contact pair |
| `LfpMontageTimeDomain` | BrainSense Survey time series |
| `BrainSenseTimeDomain` | BrainSense Streaming time series |
| `BrainSenseLfp` | Stimulation amplitude during Streaming |
| `IndefiniteStreaming` | Indefinite Streaming time series |
| `Groups` / `GroupHistory` | Stimulation settings, sensing contacts, frequency of interest, aDBS-related fields |
| `SessionDate` | Ordering sessions and defining epochs |

### File-name conventions (optional but recommended)

Information in file names is parsed automatically:

| Pattern | Example | Parsed as |
|---|---|---|
| Patient ID | `DBS-038` | Patient label |
| Dystonia severity | `BFMDS 49.5`, `BFMDRS_7`, `BFMDS_49_5` | BFMDRS score (underscore read as a decimal point) |
| Chorea severity | `UHDRS 12`, `UHDRS_12_5`, `UHDRS-TMS 30`, `uhdrs chorea 8` | UHDRS score |

Matching is case-insensitive. A file can carry both scores. Missing scores can be entered in the app (see [Severity scores and annotations](#severity-scores-and-annotations)).

---

## Session selection and multi-session comparison

Sessions are listed chronologically as **epochs** (E1, E2, ...), labelled with any severity scores, for example `E3 (BFM 22, UHDRS 8)`.

- **Use** column: tick the sessions to analyse. **All** and **None** select or clear every session.
- Clicking a row (not the checkbox) shows that file's details in the info box: patient, date, scores, sensing contacts and frequency of interest, and data counts.
- **Epoch definition:** epoch *k* contains Timeline samples recorded after session *k−1* and up to session *k*. Samples repeated across overlapping exports are de-duplicated, so none is counted twice.

---

## Tabs and features

### Overview
One row per session:
- date and severity scores
- active stimulation group
- left and right amplitude, rate, pulse width and active contacts (e.g. `Case+ E1-`)
- stimulation amplitude actually logged in the Timeline during that epoch, as median [min–max]
- sensing contact pair and frequency of interest (FOI)
- an aDBS indicator
- available modalities (Survey, Streaming, Timeline, Events)

Two plots show programmed amplitude with the Timeline range, and stimulation rate against sensing FOI, across sessions. Clicking a row lists the full stimulation details and every adaptive, threshold, limit, capture or ramp field found in the file.

### Timeline
- Chronic LFP power for each hemisphere, with a 24-h moving median, alternating epoch shading and labels, and patient-marked event markers.
- **Stimulation amplitude panel** beneath it, with a linked x-axis.
- **24-h profile** in 10-min bins: all data, by severity-score group (high vs. low; the score and threshold are set in the Stats tab), or one line per epoch. Dotted lines show the interquartile range.

### Timeline 3D
Surfaces with date on one axis, hour of day on the other, and artifact-cleaned power as height and colour.
- **Layouts:** sessions side by side (columns), sessions stacked (rows), or one continuous surface across all ticked sessions.
- **Z:** log₁₀ power, raw power, or a z-score of log₁₀ power within each panel (to compare day/night shape when overall power differs).
- **Noise correction:**
  - artifact removal, using the global *Artifact k* setting;
  - a median within each 10-min cell;
  - optional filling of gaps of 30 min or less;
  - optional 3 × 3 or 5 × 5 median smoothing, which never fills real gaps.
- **Shared colour/z scale** across panels, **linked rotation**, and a **top-down** heatmap view.

### Circadian compare
Overlays the 24-h profiles of the ticked sessions, with Left and Right in separate panels on a shared y-axis.
- **Data per session:** its epoch only, or everything stored in that file.
- **Normalization:** none, divide by the file median, or z-score of log power.
- **Cosinor table:** MESOR, amplitude, relative amplitude, acrophase (clock time) and R² for each session and hemisphere.
- **Pop out figure** redraws the comparison in a regular MATLAB figure for saving or editing.

### Events
- Table of patient-marked events in the ticked sessions, filterable by event type. Clicking an event shows its snapshot spectra.
- **Compare median spectra:** group by event type, event type × session, checked events by type, or individual checked events. Left and Right are shown in separate panels with the interquartile range.
- Mean beta power per event is compared across groups: Mann–Whitney U with Cliff's delta for two groups, or Kruskal–Wallis with Dunn–Holm for three or more.

### Survey: frequency
`LFPMontage` spectra with Left and Right in separate panels:
- all contact pairs for one session;
- one contact pair across the ticked sessions;
- mean beta magnitude per contact × session as grouped bars.

Spectra flagged by the device's artifact status are marked. The table lists mean beta magnitude, beta peak frequency, and the device-reported peak, sorted by beta within each hemisphere.

### Survey: time domain
Beta-burst analysis of `LfpMontageTimeDomain` recordings, for one session or all ticked sessions.
- **Band:** the global beta band, or each channel's individual peak ± 3 Hz.
- **Threshold:** pooled per session and hemisphere (default), or per channel.
- **Plots:** envelope with burst shading, Welch PSD, and a burst-duration histogram.
- **Comparison:** per-channel bars, grouped by session when several are analysed.
- **Metrics:** burst rate, mean and median duration, % long bursts (> 400 ms), % time in burst, mean amplitude, peak frequency, and mean beta PSD.

### Streaming
Analysis of one BrainSense Streaming or Indefinite Streaming recording:
- spectrogram (turbo) and Welch PSD, with the device FOI marked;
- **stimulation amplitude panel** (from `BrainSenseLfp`), time-locked to the spectrogram;
- beta bursts (smoothed Hilbert envelope with a percentile threshold);
- phase–amplitude coupling, as a Tort modulation index with 200 circular-shift surrogates, and an optional **comodulogram**;
- **severity score** for the recording (inherited from the session or entered manually);
- **segment annotation:**
  - **Stim steps** creates one segment per stable stimulation amplitude lasting at least 5 s;
  - **Add view** adds a segment for the time range currently shown;
  - **Clear segs** removes all segments.

  The segment table shows median L/R mA, mean beta power (dB) and editable BFMDRS/UHDRS scores for each segment.

### Streaming compare
One column per ticked session: Left spectrogram, Right spectrogram, and stimulation amplitude.
- Spectrograms share one colour scale by default, so colour means the same power in every panel.
- **Recording per session:** longest, first, or last.
- **Burst threshold:** pooled across sessions per hemisphere (default), so a drop in beta amplitude shows up as fewer or shorter bursts.
- Overlaid PSDs, either absolute or as % of 1–100 Hz power.
- **Metrics table:** score, median stimulation, peak frequency, relative beta power, burst metrics, and aperiodic exponent.

### Periodic / aperiodic
Spectral parameterization of survey spectra, survey time series (Welch), or streaming (Welch).
- **FOOOF (fixed or knee):** a port of the FOOOF 1.x algorithm that reproduces the Python `fooof` package on test spectra. It reports offset, exponent, knee, R², error, and Gaussian peaks (centre frequency, power, bandwidth).
- **IRASA:** separates the aperiodic and periodic components of time-series data.
- **Fit all items** fits every item in the ticked sessions and produces a table with scores.
- **Compare sessions** fits the same contact or channel in every ticked session, overlays the aperiodic fits and flattened spectra, and summarises trends, e.g. `Exponent: 1.42 -> 1.31 -> 1.18`.
- **Edit scores...** opens the session score editor.

### Stats
Statistics on Timeline LFP power, grouped by epoch or by severity score (high vs. low on BFMDRS or UHDRS, with a chosen or median threshold).
- **Unit of analysis:** daily medians (default, with a minimum day-coverage setting) or 10-min samples. The latter triggers a warning, because those samples are autocorrelated.
- **Tests:**
  - Kruskal–Wallis with Dunn post hoc (Holm-adjusted) and ε²;
  - Mann–Whitney U with Cliff's delta;
  - Jonckheere–Terpstra trend test (increasing, decreasing or two-sided);
  - Theil–Sen slope;
  - Spearman correlation.
- Box plots with individual data points. The group summary includes scores and exports to CSV.

---

## Severity scores and annotations

| Level | Source | How to edit |
|---|---|---|
| Session | File name (BFMDRS / UHDRS) | **Edit scores...** (Periodic / aperiodic or Stats tab). A manual value fills a missing score or overrides one; enter `NaN` to remove it. |
| Streaming recording | Inherits the session score | Score boxes on the Streaming tab, then **Save score**. |
| Streaming segment | Blank | Edit the BFMDRS / UHDRS cells in the segment table. |

Manual session values are marked with **\*** wherever session labels appear, e.g. `E3 (BFM 22*)`, so they are never mistaken for scores parsed from file names. Manual scores feed the score groupings in Stats and the Timeline 24-h profile.

> Manual scores and segment annotations are kept **in memory only**. They are lost when the app closes, and nothing is written back to the JSON files.

---

## Global settings

These are in the left panel.

| Setting | Effect |
|---|---|
| Time zone | Converts UTC device timestamps to local time for all dates and hour-of-day calculations. Any IANA name can be typed (default `America/Phoenix`). |
| Hemisphere | Left, Right, or Both, for Timeline-based plots and Stats. |
| Artifact k (scaled MAD) | Outlier threshold for Timeline cleaning (`isoutlier`, 25-sample moving median). |
| Min day coverage | Fraction of the 144 ten-minute bins a day needs to count as a daily median. |
| Beta band (Hz) | Band used for shading, burst detection, beta metrics, and beta-peak selection in fits. |
| Log y-axis | Log scaling for Timeline, profile, and Stats plots. |

---

## Exporting results

- **Export current tab as PNG...** saves every plot in the open tab at 300 dpi.
- **Export CSV...** is available in Survey: time domain (burst table), Periodic / aperiodic (fit and comparison tables), and Stats (group summary, plus a `_results.txt` file with the full test output).
- **Pop out figure** (Circadian compare) opens a standard MATLAB figure for publication edits.

---

## Methods reference

| Method | Implementation |
|---|---|
| Band-pass filtering | Zero-phase FFT-domain filter with raised-cosine edges and 1-s reflection padding |
| Analytic signal / envelope | FFT-based Hilbert transform; envelope smoothed over 200 ms |
| PSD | Welch, Hann window, 50% overlap, one-sided density |
| Spectrogram | Short-time FFT, Hann window, 90% overlap |
| Beta bursts | Envelope above a percentile threshold, minimum duration; first and last second excluded |
| PAC | Tort modulation index (18 phase bins), 200 circular-shift surrogates (shift ≥ 1 s) |
| Aperiodic / periodic | FOOOF 1.x algorithm (fixed / knee), IRASA (*h* = 1.1–1.9) |
| Circadian rhythm | Single-component 24-h cosinor (least squares) |
| Statistics | Rank-based tests with tie corrections; Holm adjustment; asymptotic p-values |

---

## Conventions

- **Time:** device timestamps are UTC and are converted to the selected time zone everywhere.
- **Colours:** heatmaps, spectrograms and surfaces use **turbo**. Multi-series colours are sampled from turbo, with Left at the blue end and Right at the red-orange end.
- **Data tips** show values in plot units, with real dates on date axes and series names where available. Shaded regions never block them.
- **Navigation:** zoom and pan with the axes toolbar. Date tick labels refresh when you pause zooming.

---

## Known limitations

- **aDBS detection** is heuristic. aDBS field names vary across firmware versions, so the Overview flags "ON?" only when an adaptive mode or status field has a non-off value, and lists the raw fields for you to check.
- **Stimulation artifact:** recordings made with stimulation on contain artifact and harmonics. Interpret high-frequency power, PAC, and comparisons between sessions recorded at different amplitudes with caution.
- **Comodulogram** values are raw MI without surrogate correction. Confirm hot spots with the single-pair PAC analysis.
- **Short recordings** (Survey time domain, roughly 20 s) give noisy burst and PAC estimates at low frequencies.
- **Indefinite Streaming** has no stimulation trace, because `BrainSenseLfp` is recorded only during BrainSense Streaming.
- **No saving:** manual scores and annotations are not saved between sessions.
- **No dual-target support:** sensing contact and FOI are taken from the active group at session end, and dual-target configurations with four leads are not handled specially.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| A tab says "no data in ticked sessions" | Tick the relevant sessions in the left panel, and check that the file actually contains that modality (see the Overview *Survey / Streaming / Timeline / Events* columns). |
| Survey spectra show 0 entries | Run `fieldnames(jsondecode(fileread('file.json')))` and check for an `LFPMontage`-like block; send the output to the maintainer if its name differs. |
| Hour-of-day patterns look shifted | Set the correct **Time zone**. |
| Scores missing from labels | Check the file-name pattern, or enter the scores with **Edit scores...** |
| Controls cut off on a small screen | Use the window scroll bars; the layout keeps a minimum size and scrolls below about 1360 × 840. |
| Gap filling has no effect in Timeline 3D | Your MATLAB release does not support `fillmissing(..., 'MaxGap', ...)` (R2021b+). |
