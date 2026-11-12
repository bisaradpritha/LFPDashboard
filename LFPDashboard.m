function LFPDashboard()
% LFPDASHBOARD  Interactive dashboard for Medtronic Percept (BrainSense) JSON exports.
%
%   >> LFPDashboard
%
%   Base MATLAB only: no Signal Processing or Statistics toolbox calls
%   (filters, Hilbert transform, Welch PSD, STFT, percentiles and all tests
%   are implemented below). Target release: R2021a or newer.
%
%   SESSION SELECTION
%   Every tab works on the sessions ticked in the left-panel table, so any
%   2+ sessions can be compared (e.g. before / after a programming change).
%
%   TABS
%   Overview   One row per session: stimulation settings (amplitude, rate,
%              pulse width, contacts, aDBS-related fields), sensing contacts
%              and frequency of interest, Timeline mA range, modalities.
%   Timeline   Chronic BrainSense Timeline (LFPTrendLogs) per hemisphere with
%              24-h moving median, epochs (one per file) and event markers;
%              stimulation amplitude panel underneath (x-axes linked);
%              manual events (add by dialog or by clicking the plot; edit,
%              delete, import/export CSV);
%              24-h profile in 10-min bins (all data / by score group / by epoch).
%   Timeline   3-D surfaces (date x hour of day x artifact-cleaned power) per
%   3D         session and hemisphere, side by side, stacked or one surface.
%   Circadian  Pick 2+ files; 24-h profiles per file, Left and Right in
%   compare    separate panels, optional normalization, cosinor summary.
%   Events     Patient-marked events; LfpFrequencySnapshotEvents spectra for
%              the selected event, and mean +/- SEM spectrum per event type.
%   Survey:    BrainSense Survey spectra (LFPMontage) per contact pair, one
%   frequency  session or one contact across sessions; beta summary table.
%   Survey:    BrainSense Survey time series (LfpMontageTimeDomain): beta
%   time dom.  bursts per channel, pooled or per-channel threshold, fixed or
%              individual-peak band; per-channel comparison and CSV export.
%   Streaming  BrainSense Streaming / Indefinite Streaming time series with
%              the stimulation amplitude trace (BrainSenseLfp); severity score
%              per recording and per annotated segment (e.g. stim steps):
%              spectrogram, Welch PSD, beta bursts (envelope threshold),
%              phase-amplitude coupling (Tort MI + surrogates, comodulogram).
%   Streaming  BrainSense Streaming of the selected sessions side by side
%   compare    (shared turbo colour scale), overlaid PSDs and a metrics table.
%   Periodic / Spectral parameterization: FOOOF-style fits (fixed / knee
%   aperiodic  aperiodic + Gaussian peaks) and IRASA, for survey spectra,
%              survey time series or streaming; batch fits with CSV export.
%   Stats      Timeline power by epoch or clinical-score group (BFMDRS or
%              UHDRS, parsed from file names): Kruskal-Wallis + Dunn
%              (Holm), Jonckheere-Terpstra, Theil-Sen, Spearman,
%              Mann-Whitney U + Cliff's delta.
%
%   All heatmaps / surfaces use turbo, and multi-series line colours are
%   sampled from turbo. The window scrolls when it is smaller than the layout.
%
%   SEVERITY SCORES
%   BFMDRS / UHDRS come from file names. Missing values can be entered (or
%   overridden) with "Edit scores..." (Periodic / Stats tabs); manual values
%   are marked * in labels. Streaming recordings and segments can carry their
%   own score. Annotations live in memory only (not written back to files).
%
%   CONVENTIONS
%   * Percept timestamps are UTC. Everything shown (dates, hour of day,
%     daily medians) is converted to the time zone in the left panel.
%   * Epoch k = Timeline samples recorded after session k-1 and up to
%     session k (SessionDate of each JSON, sorted). Samples repeated across
%     overlapping files are de-duplicated, so none is counted twice.
%   * 10-min Timeline samples are autocorrelated, so "Daily median" is the
%     default unit for statistics (days below the coverage threshold dropped).

%% ================================================================ state
S.files      = emptyFiles();
S.tl         = struct('L', emptyTL(), 'R', emptyTL());
S.events     = emptyEvents();
S.streams    = emptyStreams();
S.montage    = emptyMontage();
S.surveyTD   = emptyStreams();
S.fileTL     = {};
S.tdLast     = [];
S.tdTable    = table();
S.fitTable   = table();
S.evView     = [];
S.evChecked  = false(0, 1);
S.use        = false(0, 1);
S.sessRows   = [];
S.infoFile   = [];
S.ovRows     = [];
S.t3Link     = [];
S.stLast     = [];       % last analysed streaming recording (for segment metrics)
S.lastDir    = pwd;      % where the next file/folder dialog opens
S.manEv      = struct('dt', {}, 'name', {}, 'note', {});   % manual Timeline events (UTC)
S.statsTable = table();
S.statsText  = {};

%% ================================================================ layout
scr = get(groot, 'ScreenSize');
figW = min(1440, scr(3) - 60);
figH = min(880, scr(4) - 110);
fig  = uifigure('Name', 'LFP Dashboard', ...
    'Position', [max(20, (scr(3) - figW) / 2), max(50, (scr(4) - figH) / 2), figW, figH]);
MINW = 1360; MINH = 840;          % below this window size, scroll bars appear
outer = uigridlayout(fig, [1 1]);
outer.Padding = [0 0 0 0];
outer.Scrollable = 'on';
root = uigridlayout(outer, [1 2]);
root.ColumnWidth = {290, '1x'};

% ---------------- left panel
pnl = uipanel(root, 'Title', 'Data & global settings');
lg  = uigridlayout(pnl, [12 2]);
lg.RowHeight   = {30, 30, 24, '1x', 170, 22, 22, 22, 22, 24, 22, 30};
lg.ColumnWidth = {125, '1x'};

gLoad = uigridlayout(lg, [1 2]);
gLoad.Padding = [0 0 0 0]; gLoad.ColumnSpacing = 6;
place(gLoad, 1, [1 2]);
uibutton(gLoad, 'Text', 'Add files...', ...
    'Tooltip', 'Pick JSON files from any folder; repeat to add files from other folders', ...
    'ButtonPushedFcn', @(~,~) onLoad());
uibutton(gLoad, 'Text', 'Add folder...', ...
    'Tooltip', 'Load every JSON file in a folder and all of its subfolders', ...
    'ButtonPushedFcn', @(~,~) onLoadFolder());
btnClear = uibutton(lg, 'Text', 'Clear all', 'ButtonPushedFcn', @(~,~) onClear());
place(btnClear, 2, [1 2]);
gSel = uigridlayout(lg, [1 3]);
gSel.Padding = [0 0 0 0]; gSel.ColumnWidth = {'1x', 45, 50};
place(gSel, 3, [1 2]);
uilabel(gSel, 'Text', 'Sessions (tick to include)', 'FontWeight', 'bold');
uibutton(gSel, 'Text', 'All', 'ButtonPushedFcn', @(~,~) onSessAll(true));
uibutton(gSel, 'Text', 'None', 'ButtonPushedFcn', @(~,~) onSessAll(false));
tblSess = uitable(lg, 'RowName', {}, 'ColumnEditable', [true false], ...
    'CellEditCallback', @(~,evt) onSessEdit(evt), ...
    'CellSelectionCallback', @(~,evt) onSessSelect(evt));
place(tblSess, 4, [1 2]);
taInfo = uitextarea(lg, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 11);
place(taInfo, 5, [1 2]);

place(uilabel(lg, 'Text', 'Time zone'), 6, 1);
ddTZ = uidropdown(lg, 'Items', {'America/Phoenix', 'America/Denver', ...
    'America/Los_Angeles', 'America/Chicago', 'America/New_York', 'UTC'}, ...
    'Value', 'America/Phoenix', 'Editable', 'on', ...
    'Tooltip', 'Any IANA time-zone name can be typed here', ...
    'ValueChangedFcn', @(~,~) onGlobalChange());
place(ddTZ, 6, 2);

place(uilabel(lg, 'Text', 'Hemisphere'), 7, 1);
ddHemi = uidropdown(lg, 'Items', {'Left', 'Right', 'Both'}, 'Value', 'Both', ...
    'ValueChangedFcn', @(~,~) onGlobalChange());
place(ddHemi, 7, 2);

place(uilabel(lg, 'Text', 'Artifact k (scaled MAD)'), 8, 1);
spK = uispinner(lg, 'Limits', [2 20], 'Step', 0.5, 'Value', 5, ...
    'Tooltip', 'isoutlier(movmedian, 25 samples) threshold factor', ...
    'ValueChangedFcn', @(~,~) onGlobalChange());
place(spK, 8, 2);

place(uilabel(lg, 'Text', 'Min day coverage'), 9, 1);
spCov = uispinner(lg, 'Limits', [0 1], 'Step', 0.05, 'Value', 0.5, ...
    'Tooltip', 'Fraction of the 144 ten-minute bins a day needs for a daily median');
place(spCov, 9, 2);

place(uilabel(lg, 'Text', 'Beta band (Hz)'), 10, 1);
gb = uigridlayout(lg, [1 2]);
gb.Padding = [0 0 0 0]; gb.ColumnSpacing = 4;
place(gb, 10, 2);
efBetaLo = uieditfield(gb, 'numeric', 'Value', 13, 'Limits', [1 200], ...
    'ValueChangedFcn', @(~,~) onBandChange());
efBetaHi = uieditfield(gb, 'numeric', 'Value', 30, 'Limits', [2 200], ...
    'ValueChangedFcn', @(~,~) onBandChange());

chkLog = uicheckbox(lg, 'Text', 'Log y-axis (Timeline, profiles, stats)', 'Value', true, ...
    'ValueChangedFcn', @(~,~) onGlobalChange());
place(chkLog, 11, [1 2]);

btnExport = uibutton(lg, 'Text', 'Export current tab as PNG...', ...
    'ButtonPushedFcn', @(~,~) onExportTab());
place(btnExport, 12, [1 2]);

% ---------------- tabs
tg = uitabgroup(root);
tg.Layout.Row = 1; tg.Layout.Column = 2;
tabOv    = uitab(tg, 'Title', 'Overview');
tabTL    = uitab(tg, 'Title', 'Timeline');
tabT3    = uitab(tg, 'Title', 'Timeline 3D');
tabCC    = uitab(tg, 'Title', 'Circadian compare');
tabEv    = uitab(tg, 'Title', 'Events');
tabSF    = uitab(tg, 'Title', 'Survey: frequency');
tabTD    = uitab(tg, 'Title', 'Survey: time domain');
tabSt    = uitab(tg, 'Title', 'Streaming');
tabSC    = uitab(tg, 'Title', 'Streaming compare');
tabFit   = uitab(tg, 'Title', 'Periodic / aperiodic');
tabStats = uitab(tg, 'Title', 'Stats');

% ---------------- Overview tab
g0 = uigridlayout(tabOv, [2 1]);
g0.RowHeight = {'1.1x', '1x'};
tblOv = uitable(g0, 'RowName', {}, 'CellSelectionCallback', @(~,evt) onOvSelect(evt));
g0b = uigridlayout(g0, [1 3]);
g0b.ColumnWidth = {'1x', '1x', 430};
g0b.Padding = [0 0 0 0];
axOvAmp  = uiaxes(g0b);
axOvFreq = uiaxes(g0b);
taOv = uitextarea(g0b, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 10, ...
    'Value', {'Click a session row to see its stimulation / aDBS details.'});

% ---------------- Timeline tab
g1 = uigridlayout(tabTL, [4 1]);
g1.RowHeight = {62, '1.3x', 105, '1x'};
c1 = uigridlayout(g1, [2 6]);
c1.Padding = [0 0 0 0];
c1.ColumnWidth = {125, 110, 100, 160, '1x', 120};
chkEvents = uicheckbox(c1, 'Text', 'Device events', 'Value', true, ...
    'ValueChangedFcn', @(~,~) refreshTimeline());
place(chkEvents, 1, 1);
chkEpochs = uicheckbox(c1, 'Text', 'Show epochs', 'Value', true, ...
    'ValueChangedFcn', @(~,~) refreshTimeline());
place(chkEpochs, 1, 2);
place(uilabel(c1, 'Text', '24-h profile:', 'HorizontalAlignment', 'right'), 1, 3);
ddProfile = uidropdown(c1, 'Items', {'All data', 'By score group', 'By epoch'}, ...
    'Tooltip', 'Score and threshold are set in the Stats tab (BFMDRS or UHDRS)', ...
    'ValueChangedFcn', @(~,~) refreshCirc());
place(ddProfile, 1, 4);
place(uibutton(c1, 'Text', 'Redraw', 'ButtonPushedFcn', @(~,~) refreshTimelineTab()), 1, 6);
chkManEv = uicheckbox(c1, 'Text', 'Manual events', 'Value', true, ...
    'ValueChangedFcn', @(~,~) refreshTimeline());
place(chkManEv, 2, 1);
place(uibutton(c1, 'Text', 'Add event...', ...
    'Tooltip', 'Add an event at a date and time you type', ...
    'ButtonPushedFcn', @(~,~) openManEvDialog(NaN)), 2, 2);
tglPickEv = uibutton(c1, 'state', 'Text', 'Click plot to add', ...
    'Tooltip', 'While on, clicking the Timeline plot adds an event at that time', ...
    'ValueChangedFcn', @(~,~) onPickToggle());
place(tglPickEv, 2, [3 4]);
lblPickEv = uilabel(c1, 'Text', '', 'FontColor', [0.35 0.35 0.35]);
place(lblPickEv, 2, 5);
place(uibutton(c1, 'Text', 'Manage events...', ...
    'Tooltip', 'Edit, delete, import or export manual events', ...
    'ButtonPushedFcn', @(~,~) openManEvManager()), 2, 6);
axTL   = uiaxes(g1);
axStim = uiaxes(g1);
axCirc = uiaxes(g1);
% Date tick labels are rebuilt once zooming / panning pauses (debounced).
% Rebuilding them on every XLim change made interactive zoom stall.
tmTicks = timer('StartDelay', 0.35, 'ExecutionMode', 'singleShot', ...
    'TimerFcn', @(~,~) updateDateTicks());
fig.CloseRequestFcn = @(~,~) onCloseFig();
try
    for axL_ = [axTL axStim axOvAmp axOvFreq]
        addlistener(axL_, 'XLim', 'PostSet', @(~,~) queueTicks());
    end
catch
end
try
    linkaxes([axTL axStim], 'x');
catch
end

% ---------------- Timeline 3D tab
g10 = uigridlayout(tabT3, [2 1]);
g10.RowHeight = {62, '1x'};
c10 = uigridlayout(g10, [2 8]);
c10.Padding = [0 0 0 0];
c10.ColumnWidth = {55, 215, 30, 175, 55, 125, '1x', 90};
place(uilabel(c10, 'Text', 'Layout', 'HorizontalAlignment', 'right'), 1, 1);
ddT3Layout = uidropdown(c10, 'Items', {'Sessions side by side (columns)', ...
    'Sessions stacked (rows)', 'Single surface (all ticked)'});
place(ddT3Layout, 1, 2);
place(uilabel(c10, 'Text', 'Z', 'HorizontalAlignment', 'right'), 1, 3);
ddT3Z = uidropdown(c10, 'Items', {'log10 power', 'Power', 'z-score of log10 (per panel)'});
place(ddT3Z, 1, 4);
place(uilabel(c10, 'Text', 'Smooth', 'HorizontalAlignment', 'right'), 1, 5);
ddT3Smooth = uidropdown(c10, 'Items', {'None', '3 x 3 median', '5 x 5 median'}, 'Value', '3 x 3 median');
place(ddT3Smooth, 1, 6);
place(uibutton(c10, 'Text', 'Plot', 'ButtonPushedFcn', @(~,~) onT3Plot()), 1, 8);
chkT3Fill = uicheckbox(c10, 'Text', 'Fill gaps <= 30 min', 'Value', true);
place(chkT3Fill, 2, [1 2]);
chkT3Shared = uicheckbox(c10, 'Text', 'Shared colour/z scale', 'Value', true);
place(chkT3Shared, 2, 4);
ddT3View = uidropdown(c10, 'Items', {'3-D view', 'Top-down (heatmap)'});
place(ddT3View, 2, [5 6]);
chkT3Link = uicheckbox(c10, 'Text', 'Link rotation', 'Value', true);
place(chkT3Link, 2, 7);
pT3 = uipanel(g10, 'BorderType', 'none');
gT3 = uigridlayout(pT3, [2 1]);
gT3.Padding = [0 0 0 0];
gT3.Scrollable = 'on';

% ---------------- Circadian compare tab
g5 = uigridlayout(tabCC, [1 2]);
g5.ColumnWidth = {300, '1x'};
g5L = uigridlayout(g5, [6 1]);
g5L.RowHeight = {22, '1x', 22, 22, 22, 30};
g5L.Padding = [0 0 0 0];
uilabel(g5L, 'Text', 'Sessions ticked in the left panel:');
taCCSel = uitextarea(g5L, 'Editable', 'off', 'FontSize', 11);
ddCCScope = uidropdown(g5L, 'Items', {'Epoch (non-overlapping)', 'All samples in file'}, ...
    'Tooltip', 'Epoch: data since the previous session only. All samples: everything stored in that JSON.');
ddCCNorm = uidropdown(g5L, 'Items', {'No normalization', 'Divide by file median', 'z-score of log power'}, ...
    'Tooltip', 'Normalize to compare profile shape across sessions');
chkCCIQR = uicheckbox(g5L, 'Text', 'Show IQR (dotted)', 'Value', false);
gCCb = uigridlayout(g5L, [1 2]);
gCCb.Padding = [0 0 0 0];
uibutton(gCCb, 'Text', 'Plot', 'ButtonPushedFcn', @(~,~) onCCPlot());
uibutton(gCCb, 'Text', 'Pop out figure', 'ButtonPushedFcn', @(~,~) onCCPopout());
g5R = uigridlayout(g5, [2 2]);
g5R.RowHeight = {'2x', '1x'};
g5R.Padding = [0 0 0 0];
axCCL = uiaxes(g5R); place(axCCL, 1, 1);
axCCR = uiaxes(g5R); place(axCCR, 1, 2);
tblCC = uitable(g5R); place(tblCC, 2, [1 2]);

% ---------------- Events tab
g2 = uigridlayout(tabEv, [1 2]);
g2.ColumnWidth = {480, '1x'};
g2L = uigridlayout(g2, [4 1]);
g2L.RowHeight = {22, 90, 30, '1x'};
g2L.Padding = [0 0 0 0];
uilabel(g2L, 'Text', 'Event types (Ctrl/Shift-click; none selected = all)');
lbEvTypes = uilistbox(g2L, 'Items', {}, 'Multiselect', 'on', ...
    'ValueChangedFcn', @(~,~) onEvTypeChange());
g2Lc = uigridlayout(g2L, [1 4]);
g2Lc.ColumnWidth = {60, '1x', 80, 90};
g2Lc.Padding = [0 0 0 0];
uilabel(g2Lc, 'Text', 'Group by', 'HorizontalAlignment', 'right');
ddEvGroup = uidropdown(g2Lc, 'Items', {'Event type', 'Event type x session', ...
    'Checked events: by type', 'Checked events: individual'});
uibutton(g2Lc, 'Text', 'Compare', 'ButtonPushedFcn', @(~,~) onEvCompare());
uibutton(g2Lc, 'Text', 'Clear checks', 'ButtonPushedFcn', @(~,~) onEvClearChecks());
tblEv = uitable(g2L, 'RowName', {}, 'ColumnEditable', [true false false false false false], ...
    'CellSelectionCallback', @(~,evt) onEvSelect(evt), ...
    'CellEditCallback', @(~,evt) onEvEdit(evt));
g2R = uigridlayout(g2, [2 2]);
g2R.RowHeight = {'1x', '1.3x'};
g2R.Padding = [0 0 0 0];
axEvSel = uiaxes(g2R);
taEv = uitextarea(g2R, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 10);
axEvL = uiaxes(g2R);
axEvR = uiaxes(g2R);

% ---------------- Survey: frequency tab
g6 = uigridlayout(tabSF, [2 1]);
g6.RowHeight = {30, '1x'};
c6 = uigridlayout(g6, [1 8]);
c6.Padding = [0 0 0 0];
c6.ColumnWidth = {55, 240, 40, 215, 55, 150, 70, '1x'};
uilabel(c6, 'Text', 'Session', 'HorizontalAlignment', 'right');
ddSFSess = uidropdown(c6, 'Items', {'(no LFPMontage data)'}, 'ItemsData', 0, ...
    'ValueChangedFcn', @(~,~) refreshSurveyFreqPlot());
uilabel(c6, 'Text', 'View', 'HorizontalAlignment', 'right');
ddSFView = uidropdown(c6, 'Items', {'All contacts, one session', 'One contact, across sessions', ...
    'Beta per contact, across sessions'}, ...
    'ValueChangedFcn', @(~,~) refreshSurveyFreqPlot());
uilabel(c6, 'Text', 'Contact', 'HorizontalAlignment', 'right');
ddSFContact = uidropdown(c6, 'Items', {'(none)'}, 'ValueChangedFcn', @(~,~) refreshSurveyFreqPlot());
chkSFLog = uicheckbox(c6, 'Text', 'Log y', 'Value', true, 'ValueChangedFcn', @(~,~) refreshSurveyFreqPlot());
uilabel(c6, 'Text', '');
b6 = uigridlayout(g6, [2 2]);
b6.RowHeight = {'1.6x', '1x'};
b6.Padding = [0 0 0 0];
axSFL = uiaxes(b6); place(axSFL, 1, 1);
axSFR = uiaxes(b6); place(axSFR, 1, 2);
tblSF = uitable(b6); place(tblSF, 2, [1 2]);

% ---------------- Survey: time-domain tab
g7 = uigridlayout(tabTD, [2 1]);
g7.RowHeight = {66, '1x'};
c7 = uigridlayout(g7, [2 10]);
c7.Padding = [0 0 0 0];
c7.ColumnWidth = {60, '2x', 62, '1.3x', 62, 50, 62, 55, 125, 165};
place(uilabel(c7, 'Text', 'Session', 'HorizontalAlignment', 'right'), 1, 1);
ddTDSess = uidropdown(c7, 'Items', {'(no survey time-domain data)'}, 'ItemsData', 0, ...
    'ValueChangedFcn', @(~,~) onTDSessChange());
place(ddTDSess, 1, 2);
place(uilabel(c7, 'Text', 'Channel', 'HorizontalAlignment', 'right'), 1, 3);
ddTDChan = uidropdown(c7, 'Items', {'(none)'}, 'ItemsData', 0, ...
    'ValueChangedFcn', @(~,~) onTDChannelChange());
place(ddTDChan, 1, 4);
place(uilabel(c7, 'Text', 'Thr %ile', 'HorizontalAlignment', 'right'), 1, 5);
efTDThr = uieditfield(c7, 'numeric', 'Value', 75, 'Limits', [50 99]); place(efTDThr, 1, 6);
place(uilabel(c7, 'Text', 'Min ms', 'HorizontalAlignment', 'right'), 1, 7);
efTDMin = uieditfield(c7, 'numeric', 'Value', 100, 'Limits', [0 2000]); place(efTDMin, 1, 8);
place(uibutton(c7, 'Text', 'Analyze session', 'ButtonPushedFcn', @(~,~) onTDAnalyzeSession()), 1, 9);
place(uibutton(c7, 'Text', 'Analyze ticked sessions', 'ButtonPushedFcn', @(~,~) onTDAnalyzeAll()), 1, 10);
place(uilabel(c7, 'Text', 'Band', 'HorizontalAlignment', 'right'), 2, 1);
ddTDBand = uidropdown(c7, 'Items', {'Fixed (left-panel beta band)', 'Individual peak +/- 3 Hz'});
place(ddTDBand, 2, 2);
place(uilabel(c7, 'Text', 'Threshold', 'HorizontalAlignment', 'right'), 2, 3);
ddTDThrMode = uidropdown(c7, 'Items', {'Pooled per session & hemisphere', 'Per channel'}, ...
    'Tooltip', ['Per-channel percentile thresholds force a similar % time-in-burst on every ' ...
    'channel; pooling across a hemisphere''s channels keeps amplitude differences between contacts.']);
place(ddTDThrMode, 2, 4);
place(uilabel(c7, 'Text', 'Compare', 'HorizontalAlignment', 'right'), 2, 5);
ddTDMetric = uidropdown(c7, 'Items', {'Burst rate (/min)', 'Mean duration (ms)', ...
    '% long bursts (>400 ms)', '% time in burst', 'Mean burst amplitude', ...
    'Peak beta freq (Hz)', 'Mean beta PSD'}, 'ValueChangedFcn', @(~,~) plotTDComp());
place(ddTDMetric, 2, [6 8]);
place(uibutton(c7, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) onTDExport()), 2, 10);
b7 = uigridlayout(g7, [2 3]);
b7.ColumnWidth = {'1x', '1x', 470};
b7.Padding = [0 0 0 0];
axTDTrace = uiaxes(b7); place(axTDTrace, 1, [1 2]);
axTDPSD   = uiaxes(b7); place(axTDPSD, 1, 3);
axTDDur   = uiaxes(b7); place(axTDDur, 2, 1);
axTDComp  = uiaxes(b7); place(axTDComp, 2, 2);
tblTD     = uitable(b7); place(tblTD, 2, 3);

% ---------------- Streaming tab
g3 = uigridlayout(tabSt, [2 1]);
g3.RowHeight = {66, '1x'};
c3 = uigridlayout(g3, [2 9]);
c3.Padding = [0 0 0 0];
c3.ColumnWidth = {'2x', 70, 52, 70, 52, 62, 55, '1x', '1x'};
ddStream = uidropdown(c3, 'Items', {'(no streaming recordings)'}, 'ItemsData', 0, ...
    'ValueChangedFcn', @(~,~) onStreamSelect());
place(ddStream, 1, 1);
place(uilabel(c3, 'Text', 'Win (s)', 'HorizontalAlignment', 'right'), 1, 2);
efWin = uieditfield(c3, 'numeric', 'Value', 1, 'Limits', [0.25 4], ...
    'Tooltip', 'Window for spectrogram and Welch PSD');
place(efWin, 1, 3);
place(uilabel(c3, 'Text', 'Thr %ile', 'HorizontalAlignment', 'right'), 1, 4);
efThr = uieditfield(c3, 'numeric', 'Value', 75, 'Limits', [50 99]); place(efThr, 1, 5);
place(uilabel(c3, 'Text', 'Min ms', 'HorizontalAlignment', 'right'), 1, 6);
efMinDur = uieditfield(c3, 'numeric', 'Value', 100, 'Limits', [0 2000]); place(efMinDur, 1, 7);
btnAnalyze = uibutton(c3, 'Text', 'Analyze', 'ButtonPushedFcn', @(~,~) onAnalyze());
place(btnAnalyze, 1, 8);
btnComod = uibutton(c3, 'Text', 'Comodulogram', 'ButtonPushedFcn', @(~,~) onComod());
place(btnComod, 1, 9);
place(uilabel(c3, 'Text', 'Beta band is set in the left panel.', ...
    'FontColor', [0.4 0.4 0.4]), 2, 1);
place(uilabel(c3, 'Text', 'PAC phase', 'HorizontalAlignment', 'right'), 2, 2);
efPhLo = uieditfield(c3, 'numeric', 'Value', 13, 'Limits', [1 200]); place(efPhLo, 2, 3);
efPhHi = uieditfield(c3, 'numeric', 'Value', 30, 'Limits', [2 200]); place(efPhHi, 2, 4);
place(uilabel(c3, 'Text', 'PAC amp', 'HorizontalAlignment', 'right'), 2, 5);
efAmLo = uieditfield(c3, 'numeric', 'Value', 50, 'Limits', [2 500]); place(efAmLo, 2, 6);
efAmHi = uieditfield(c3, 'numeric', 'Value', 110, 'Limits', [3 500]); place(efAmHi, 2, 7);
gSeg = uigridlayout(c3, [1 4]);
gSeg.Padding = [0 0 0 0]; gSeg.ColumnSpacing = 5;
place(gSeg, 2, [8 9]);
uibutton(gSeg, 'Text', 'Stim steps', ...
    'Tooltip', 'One segment per stable stimulation amplitude (>= 5 s), ready for scoring', ...
    'ButtonPushedFcn', @(~,~) onSegStim());
uibutton(gSeg, 'Text', 'Add view', ...
    'Tooltip', 'Add a segment for the time range currently shown (zoom the spectrogram or stim panel first)', ...
    'ButtonPushedFcn', @(~,~) onSegAdd());
uibutton(gSeg, 'Text', 'Clear', 'Tooltip', 'Remove all segments of this recording', ...
    'ButtonPushedFcn', @(~,~) onSegClear());
uibutton(gSeg, 'Text', 'Seg PSDs', ...
    'Tooltip', 'Pop-out window: power spectrum of each segment overlaid, plus beta power per segment', ...
    'ButtonPushedFcn', @(~,~) onSegPSD());

b3 = uigridlayout(g3, [3 3]);
b3.ColumnWidth = {'1x', '1x', 380};
b3.RowHeight = {'1x', 150, '1x'};
b3.Padding = [0 0 0 0];
axSpec   = uiaxes(b3); place(axSpec, 1, [1 2]);
axPSD    = uiaxes(b3); place(axPSD, 1, 3);
axStimSt = uiaxes(b3); place(axStimSt, 2, [1 2]);
try
    linkaxes([axSpec axStimSt], 'x');
catch
end
gSS = uigridlayout(b3, [2 1]);
gSS.RowHeight = {52, '1x'};
gSS.Padding = [0 0 0 0]; gSS.RowSpacing = 4;
place(gSS, 2, 3);
gSSc = uigridlayout(gSS, [2 5]);
gSSc.Padding = [0 0 0 0]; gSSc.RowSpacing = 2; gSSc.ColumnSpacing = 5;
gSSc.ColumnWidth = {52, 50, 48, 50, '1x'};
place(uilabel(gSSc, 'Text', 'BFMDRS', 'HorizontalAlignment', 'right'), 1, 1);
efStB = uieditfield(gSSc, 'text', 'Placeholder', 'n/a'); place(efStB, 1, 2);
place(uilabel(gSSc, 'Text', 'UHDRS', 'HorizontalAlignment', 'right'), 1, 3);
efStU = uieditfield(gSSc, 'text', 'Placeholder', 'n/a'); place(efStU, 1, 4);
place(uibutton(gSSc, 'Text', 'Save score', ...
    'Tooltip', 'Severity for this recording; leave the session value to inherit it', ...
    'ButtonPushedFcn', @(~,~) onStreamScoreSave()), 1, 5);
lblStSrc = uilabel(gSSc, 'Text', '', 'FontColor', [0.4 0.4 0.4], 'FontSize', 10);
place(lblStSrc, 2, [1 5]);
tblStSeg = uitable(gSS, 'RowName', {}, ...
    'ColumnEditable', [false false false false false false true true], ...
    'CellEditCallback', @(~,evt) onSegEdit(evt));
axBurst  = uiaxes(b3); place(axBurst, 3, 1);
axPAC    = uiaxes(b3); place(axPAC, 3, 2);
taStream = uitextarea(b3, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 11);
place(taStream, 3, 3);

% ---------------- Streaming compare tab
g9 = uigridlayout(tabSC, [3 1]);
g9.RowHeight = {62, '1.5x', '1x'};
c9 = uigridlayout(g9, [2 6]);
c9.Padding = [0 0 0 0];
c9.ColumnWidth = {60, 130, 125, 200, '1x', 190};
place(uilabel(c9, 'Text', 'Source', 'HorizontalAlignment', 'right'), 1, 1);
ddSCSrc = uidropdown(c9, 'Items', {'Streaming', 'Indefinite'});
place(ddSCSrc, 1, 2);
place(uilabel(c9, 'Text', 'Recording/session', 'HorizontalAlignment', 'right'), 1, 3);
ddSCPick = uidropdown(c9, 'Items', {'Longest', 'First', 'Last'});
place(ddSCPick, 1, 4);
place(uibutton(c9, 'Text', 'Compare ticked sessions', 'ButtonPushedFcn', @(~,~) onSCCompare()), 1, 6);
chkSCClim = uicheckbox(c9, 'Text', 'Shared colour scale', 'Value', true);
place(chkSCClim, 2, [1 2]);
chkSCPool = uicheckbox(c9, 'Text', 'Pooled burst threshold', 'Value', true, ...
    'Tooltip', 'One percentile threshold per hemisphere across all compared sessions');
place(chkSCPool, 2, 3);
ddSCNorm = uidropdown(c9, 'Items', {'PSD: absolute', 'PSD: % of 1-100 Hz power'});
place(ddSCNorm, 2, 4);
pSC = uipanel(g9, 'BorderType', 'none');
gSC = uigridlayout(pSC, [2 1]);
gSC.Padding = [0 0 0 0];
b9 = uigridlayout(g9, [1 3]);
b9.ColumnWidth = {'1x', '1x', 560};
b9.Padding = [0 0 0 0];
axSCL = uiaxes(b9);
axSCR = uiaxes(b9);
tblSC = uitable(b9, 'RowName', {});

% ---------------- Periodic / aperiodic tab
g8 = uigridlayout(tabFit, [2 1]);
g8.RowHeight = {62, '1x'};
c8 = uigridlayout(g8, [2 9]);
c8.Padding = [0 0 0 0];
c8.ColumnWidth = {60, 160, 40, '1x', 55, 115, 70, 100, 100};
place(uilabel(c8, 'Text', 'Source', 'HorizontalAlignment', 'right'), 1, 1);
ddFitSrc = uidropdown(c8, 'Items', {'Survey (LFPMontage)', 'Survey TD (Welch)', 'Streaming (Welch)'}, ...
    'ValueChangedFcn', @(~,~) refreshFitItems());
place(ddFitSrc, 1, 2);
place(uilabel(c8, 'Text', 'Item', 'HorizontalAlignment', 'right'), 1, 3);
ddFitItem = uidropdown(c8, 'Items', {'(none)'}, 'ItemsData', 0);
place(ddFitItem, 1, 4);
place(uilabel(c8, 'Text', 'Method', 'HorizontalAlignment', 'right'), 1, 5);
ddFitMethod = uidropdown(c8, 'Items', {'FOOOF (fixed)', 'FOOOF (knee)', 'IRASA'}, ...
    'Tooltip', 'IRASA needs a time series (Survey TD or Streaming)');
place(ddFitMethod, 1, 6);
place(uibutton(c8, 'Text', 'Fit', 'ButtonPushedFcn', @(~,~) onFit()), 1, 7);
place(uibutton(c8, 'Text', 'Fit all items', 'ButtonPushedFcn', @(~,~) onFitAll()), 1, 8);
r8 = uigridlayout(c8, [1 15]);
r8.Padding = [0 0 0 0];
r8.ColumnSpacing = 5;
r8.ColumnWidth = {65, 42, 42, 70, 42, 42, 40, 40, 50, 45, 50, 40, 135, 95, '1x'};
place(r8, 2, [1 9]);
place(uibutton(c8, 'Text', 'Edit scores...', ...
    'Tooltip', 'Enter or correct BFMDRS / UHDRS per session', ...
    'ButtonPushedFcn', @(~,~) openScoreEditor()), 1, 9);
uilabel(r8, 'Text', 'Range (Hz)', 'HorizontalAlignment', 'right');
efFitLo = uieditfield(r8, 'numeric', 'Value', 3, 'Limits', [0.5 200]);
efFitHi = uieditfield(r8, 'numeric', 'Value', 40, 'Limits', [2 200]);
uilabel(r8, 'Text', 'Peak width', 'HorizontalAlignment', 'right');
efPWLo = uieditfield(r8, 'numeric', 'Value', 1, 'Limits', [0.1 50]);
efPWHi = uieditfield(r8, 'numeric', 'Value', 12, 'Limits', [0.2 100]);
uilabel(r8, 'Text', 'Peaks', 'HorizontalAlignment', 'right');
efMaxPk = uieditfield(r8, 'numeric', 'Value', 6, 'Limits', [0 20], 'RoundFractionalValues', 'on');
uilabel(r8, 'Text', 'Min ht', 'HorizontalAlignment', 'right');
efMinHt = uieditfield(r8, 'numeric', 'Value', 0.1, 'Limits', [0 5]);
uilabel(r8, 'Text', 'Thr SD', 'HorizontalAlignment', 'right');
efPkThr = uieditfield(r8, 'numeric', 'Value', 2, 'Limits', [0 10]);
chkSquare = uicheckbox(r8, 'Text', 'Square LFPMontage', 'Value', true, ...
    'Tooltip', 'Square LFPMontage magnitude (amplitude) to power before fitting');
uibutton(r8, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) onFitExport());
uibutton(r8, 'Text', 'Compare sessions', ...
    'Tooltip', 'Fit the same contact/channel in every ticked session and overlay', ...
    'ButtonPushedFcn', @(~,~) onFitCompare());
b8 = uigridlayout(g8, [2 2]);
b8.RowHeight = {'1.4x', '1x'};
b8.Padding = [0 0 0 0];
axFit  = uiaxes(b8); place(axFit, 1, 1);
axFlat = uiaxes(b8); place(axFlat, 1, 2);
taFit  = uitextarea(b8, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 11);
place(taFit, 2, 1);
tblFit = uitable(b8); place(tblFit, 2, 2);

% ---------------- Stats tab
g4 = uigridlayout(tabStats, [2 1]);
g4.RowHeight = {62, '1x'};
c4 = uigridlayout(g4, [2 8]);
c4.Padding = [0 0 0 0];
c4.ColumnWidth = {65, 175, 40, 120, 45, 105, '1x', 105};
place(uilabel(c4, 'Text', 'Grouping', 'HorizontalAlignment', 'right'), 1, 1);
ddGroup = uidropdown(c4, 'Items', {'Epochs (one per file)', 'Score high vs low'});
place(ddGroup, 1, 2);
place(uilabel(c4, 'Text', 'Unit', 'HorizontalAlignment', 'right'), 1, 3);
ddUnit = uidropdown(c4, 'Items', {'Daily median', '10-min samples'});
place(ddUnit, 1, 4);
place(uilabel(c4, 'Text', 'Trend', 'HorizontalAlignment', 'right'), 1, 5);
ddTrend = uidropdown(c4, 'Items', {'Decreasing', 'Increasing', 'Two-sided'}, ...
    'Tooltip', 'Alternative hypothesis for Jonckheere-Terpstra across epochs');
place(ddTrend, 1, 6);
place(uibutton(c4, 'Text', 'Run', 'ButtonPushedFcn', @(~,~) onRunStats()), 1, 8);
place(uilabel(c4, 'Text', 'Score', 'HorizontalAlignment', 'right'), 2, 1);
ddScore = uidropdown(c4, 'Items', {'BFMDRS', 'UHDRS'}, ...
    'Tooltip', 'Clinical score parsed from file names; also used by the Timeline "By score group" profile', ...
    'ValueChangedFcn', @(~,~) refreshCirc());
place(ddScore, 2, 2);
place(uilabel(c4, 'Text', 'Thr', 'HorizontalAlignment', 'right'), 2, 3);
efBFM = uieditfield(c4, 'text', 'Value', '', 'Placeholder', 'median', ...
    'Tooltip', 'High/low split; blank = median of the chosen score across sessions', ...
    'ValueChangedFcn', @(~,~) refreshCirc());
place(efBFM, 2, 4);
place(uibutton(c4, 'Text', 'Edit scores...', ...
    'Tooltip', 'Enter or correct BFMDRS / UHDRS per session', ...
    'ButtonPushedFcn', @(~,~) openScoreEditor()), 2, 6);
place(uibutton(c4, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) onExportStats()), 2, 8);
b4 = uigridlayout(g4, [1 2]);
b4.ColumnWidth = {'1x', 520};
b4.Padding = [0 0 0 0];
axStats = uiaxes(b4);
taStats = uitextarea(b4, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 11);

refreshAll();
fig.AutoResizeChildren = 'off';
fig.SizeChangedFcn = @(~,~) onResize();
onResize();

%% ================================================================ window
    function queueTicks()
        try
            if strcmp(tmTicks.Running, 'on'), stop(tmTicks); end
            start(tmTicks);
        catch
        end
    end

    function updateDateTicks()
        for ax = [axTL axStim axOvAmp axOvFreq]
            if isvalid(ax), setDateTicks(ax); end
        end
    end

    function onCloseFig()
        try
            stop(tmTicks);
            delete(tmTicks);
        catch
        end
        delete(fig);
    end

    function onResize()
        % Fixed-size content (=> scroll bars) when the window is smaller
        % than the layout's minimum; otherwise stretch to fill.
        pos = fig.Position;
        if pos(3) < MINW, outer.ColumnWidth = {MINW}; else, outer.ColumnWidth = {'1x'}; end
        if pos(4) < MINH, outer.RowHeight = {MINH}; else, outer.RowHeight = {'1x'}; end
    end

%% ================================================================ callbacks: data
    function onLoad()
        % Files accumulate across calls, so each call can come from a
        % different folder. The dialog reopens in the last folder used.
        [fn, fp] = uigetfile({'*.json', 'Percept JSON (*.json)'}, ...
            'Add Percept JSON files (repeat to add from other folders)', S.lastDir, 'MultiSelect', 'on');
        figure(fig);
        if isequal(fn, 0), return; end
        S.lastDir = fp;
        fn = cellstr(fn);
        loadPaths(fullfile(fp, fn));
    end

    function onLoadFolder()
        d = uigetdir(S.lastDir, 'Add a folder (JSON files in all subfolders are included)');
        figure(fig);
        if isequal(d, 0), return; end
        S.lastDir = d;
        L = dir(fullfile(d, '**', '*.json'));
        L = L(~[L.isdir]);
        if isempty(L)
            uialert(fig, 'No JSON files were found in that folder or its subfolders.', 'Add folder');
            return;
        end
        paths = fullfile({L.folder}, {L.name});
        nNew = sum(~ismember(paths, {S.files.path}));
        sel = uiconfirm(fig, sprintf(['Found %d JSON file(s) in this folder and its subfolders ' ...
            '(%d not loaded yet). Load them?'], numel(paths), nNew), 'Add folder', ...
            'Options', {'Load', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
        if ~strcmp(sel, 'Load'), return; end
        loadPaths(paths);
    end

    function loadPaths(paths)
        % Parse and merge JSON files given as full paths (any folders).
        paths = cellstr(paths);
        dlg = uiprogressdlg(fig, 'Title', 'Loading JSON', 'Value', 0);
        warn  = {};
        nOK = 0;
        for k = 1:numel(paths)
            fpath = paths{k};
            [~, nm, ext] = fileparts(fpath);
            dlg.Value = (k - 1) / numel(paths);
            dlg.Message = [nm ext];
            if any(strcmp({S.files.path}, fpath))
                warn{end+1} = [nm ext ': already loaded']; %#ok<AGROW>
                continue;
            end
            try
                P = parsePerceptFile(fpath);
            catch ME
                warn{end+1} = sprintf('%s: not a readable Percept session (%s)', [nm ext], ME.message); %#ok<AGROW>
                continue;
            end
            F = P.file;
            if F.nL + F.nR + F.nEv + F.nStr + F.nMon + F.nTD == 0 && isnat(F.sessionDate)
                warn{end+1} = [nm ext ': no Percept data found (skipped)']; %#ok<AGROW>
                continue;
            end
            % same session exported/copied into another folder?
            dup = false;
            for q = 1:numel(S.files)
                if strcmp(S.files(q).name, F.name) && isequal(S.files(q).sessionDate, F.sessionDate)
                    dup = true;
                    warn{end+1} = sprintf('%s: same session already loaded from %s', ...
                        [nm ext], fileparts(S.files(q).path)); %#ok<AGROW>
                    break;
                end
            end
            if dup, continue; end
            S.files = [S.files; F];
            fi = numel(S.files);
            S.use(fi, 1) = true;
            S.fileTL{fi} = P.tl;
            for hc = {'L', 'R'}
                h = hc{1};
                S.tl.(h).dt  = [S.tl.(h).dt;  P.tl.(h).dt];
                S.tl.(h).v   = [S.tl.(h).v;   P.tl.(h).v];
                S.tl.(h).amp = [S.tl.(h).amp; P.tl.(h).amp];
            end
            S.events   = [S.events;   P.events];
            S.streams  = [S.streams;  setFileIdx(P.streams, fi)];
            S.surveyTD = [S.surveyTD; setFileIdx(P.surveyTD, fi)];
            S.montage  = [S.montage;  setFileIdx(P.montage, fi)];
            nOK = nOK + 1;
        end
        close(dlg);
        if nOK > 0
            dedupe();
            S.evChecked = false(numel(S.events), 1);
            S.stLast = [];
            refreshAll();
        end
        if ~isempty(warn)
            uialert(fig, sprintf('Loaded %d of %d file(s).\n\n%s', nOK, numel(paths), ...
                strjoin(warn, newline)), 'Some files were skipped', 'Icon', 'warning');
        end
    end

    function dedupe()
        for hc = {'L', 'R'}
            h = hc{1};
            T = S.tl.(h);
            keep = ~isnat(T.dt);
            [d, ia] = unique(T.dt(keep));
            vv = T.v(keep); aa = T.amp(keep);
            S.tl.(h) = struct('dt', d, 'v', vv(ia), 'amp', aa(ia));
        end
        if ~isempty(S.events)
            key = string(vertcat(S.events.dt)) + "|" + string({S.events.name}');
            [~, ia] = unique(key, 'stable');
            S.events = S.events(ia);
            [~, o] = sort(vertcat(S.events.dt));
            S.events = S.events(o);
        end
        if ~isempty(S.streams)
            key = string(vertcat(S.streams.t0)) + "|" + string({S.streams.channel}') ...
                + "|" + string({S.streams.source}');
            [~, ia] = unique(key, 'stable');
            S.streams = S.streams(ia);
        end
    end

    function onClear()
        S.files   = emptyFiles();
        S.tl      = struct('L', emptyTL(), 'R', emptyTL());
        S.events  = emptyEvents();
        S.streams = emptyStreams();
        S.montage  = emptyMontage();
        S.surveyTD = emptyStreams();
        S.fileTL   = {};
        S.tdLast   = [];
        S.tdTable  = table();
        S.fitTable = table();
        S.evView  = [];
        S.evChecked = false(0, 1);
        S.stLast = [];
        S.manEv = struct('dt', {}, 'name', {}, 'note', {});
        S.use = false(0, 1);
        S.sessRows = [];
        S.infoFile = [];
        S.statsTable = table();
        S.statsText  = {};
        for ax = [axOvAmp axOvFreq axTL axStim axCirc axCCL axCCR axEvSel axEvL axEvR axSFL axSFR ...
                axTDTrace axTDPSD axTDDur axTDComp axSpec axStimSt axPSD axBurst axPAC axSCL axSCR ...
                axFit axFlat axStats]
            clearAxes(ax); legend(ax, 'off'); title(ax, '');
        end
        delete(gSC.Children);
        for tb = [tblOv tblCC tblSF tblTD tblSC tblFit tblStSeg]
            tb.Data = table();
        end
        taEv.Value = {''};
        taStream.Value = {''};
        taFit.Value    = {''};
        taStats.Value  = {''};
        refreshAll();
    end

    function onGlobalChange()
        refreshAll();
    end

    function onBandChange()
        refreshSurveyFreqPlot();
    end

    function refreshAll()
        refreshFileList();
        refreshAfterSelection();
    end

    function refreshAfterSelection()
        refreshOverview();
        refreshTimelineTab();
        refreshCCList();
        refreshEventsTab();
        refreshSurveyFreq();
        refreshSurveyTDList();
        refreshStreamList();
        refreshFitItems();
    end

%% ================================================================ session selection
    function fis = selFiles()
        fis = find(S.use(:))';
    end

    function ks = selEpochs()
        E = getEpochs();
        if isempty(E), ks = []; return; end
        ks = find(S.use([E.fileIdx]))';
    end

    function fis = selFilesChrono()
        E = getEpochs();
        ks = selEpochs();
        fis = [E(ks).fileIdx];
    end

    function onSessEdit(evt)
        r = evt.Indices(1);
        if r > numel(S.sessRows), return; end
        S.use(S.sessRows(r)) = logical(evt.NewData);
        refreshAfterSelection();
    end

    function onSessSelect(evt)
        if isempty(evt.Indices), return; end
        r = evt.Indices(1, 1);
        if r > numel(S.sessRows), return; end
        S.infoFile = S.sessRows(r);
        showFileInfo();
    end

    function onSessAll(v)
        S.use(:) = v;
        refreshAll();
    end

    function refreshFileList()
        E = getEpochs();
        if isempty(E)
            tblSess.Data = table();
            S.sessRows = [];
        else
            S.sessRows = [E.fileIdx];
            lbl = cell(numel(E), 1);
            for k = 1:numel(E)
                lbl{k} = sprintf('%s  %s', E(k).label, S.files(E(k).fileIdx).name);
            end
            tblSess.Data = table(S.use(S.sessRows), lbl, 'VariableNames', {'Use', 'Session'});
            tblSess.ColumnWidth = {40, 'auto'};
        end
        if isempty(S.infoFile) || S.infoFile > numel(S.files)
            if isempty(E), S.infoFile = []; else, S.infoFile = E(end).fileIdx; end
        end
        showFileInfo();
    end

    function showFileInfo()
        if isempty(S.files) || isempty(S.infoFile)
            taInfo.Value = {'No files loaded.'};
            return;
        end
        F = S.files(S.infoFile);
        sd = localTime(F.sessionDate);
        [bv, uv, bs, us] = sessScore(S.infoFile);
        bfmStr = [num2s(bv) bs];
        uStr = [num2s(uv) us];
        taInfo.Value = {
            F.name
            sprintf('Folder  : %s', fileparts(F.path))
            sprintf('Patient : %s', F.patientId)
            sprintf('Session : %s', char(string(sd, 'yyyy-MM-dd HH:mm')))
            sprintf('BFMDRS  : %s   UHDRS: %s', bfmStr, uStr)
            sprintf('Sense L : %s @ %g Hz', F.sens.chL, F.sens.foiL)
            sprintf('Sense R : %s @ %g Hz', F.sens.chR, F.sens.foiR)
            sprintf('Timeline: L %d / R %d samples', F.nL, F.nR)
            sprintf('Events  : %d   Streams: %d', F.nEv, F.nStr)
            sprintf('Survey  : %d spectra, %d TD channels', F.nMon, F.nTD)};
    end

%% ================================================================ helpers that need state
    function tz = tzName()
        tz = ddTZ.Value;
        try
            datetime('now', 'TimeZone', tz);
        catch
            tz = 'UTC';
        end
    end

    function d = localTime(d)
        d.TimeZone = tzName();
    end

    function hs = selHemis()
        switch ddHemi.Value
            case 'Left',  hs = {'L'};
            case 'Right', hs = {'R'};
            otherwise,    hs = {'L', 'R'};
        end
    end

    function [dtLocal, v, dtUTC] = getTL(h)
        % Timeline for one hemisphere with artifact samples set to NaN.
        T = S.tl.(h);
        dtUTC = T.dt;
        v = T.v;
        if ~isempty(v)
            bad = isoutlier(v, 'movmedian', 25, 'ThresholdFactor', spK.Value);
            v(bad) = NaN;
        end
        dtLocal = localTime(dtUTC);
    end

    function [dt, v, dtU, ep] = getTLsel(h)
        % Timeline restricted to the ticked sessions' epochs.
        [dt, v, dtU] = getTL(h);
        ep = assignEpoch(dtU, getEpochs());
        keep = ismember(ep, selEpochs());
        dt = dt(keep); v = v(keep); dtU = dtU(keep); ep = ep(keep);
    end

    function E = getEpochs()
        E = struct('fileIdx', {}, 'tStart', {}, 'tEnd', {}, 'bfm', {}, 'uhdrs', {}, 'label', {});
        n = numel(S.files);
        if n == 0, return; end
        sd = vertcat(S.files.sessionDate);
        [sdS, o] = sort(sd);
        for k = 1:n
            E(k).fileIdx = o(k);
            E(k).tEnd = sdS(k);
            if k == 1
                E(k).tStart = sdS(1) - years(100);
            else
                E(k).tStart = sdS(k - 1);
            end
            [b, u, bs, us] = sessScore(o(k));
            E(k).bfm = b;
            E(k).uhdrs = u;
            sc = {};
            if ~isnan(b), sc{end+1} = sprintf('BFM %g%s', b, bs); end %#ok<AGROW>
            if ~isnan(u), sc{end+1} = sprintf('UHDRS %g%s', u, us); end %#ok<AGROW>
            if isempty(sc)
                E(k).label = sprintf('E%d', k);
            else
                E(k).label = sprintf('E%d (%s)', k, strjoin(sc, ', '));
            end
        end
    end

    function [grp, thr, snm] = bfmGroups(E)
        % grp(k) = 1 (low) / 2 (high) / NaN (no score) per epoch, using the
        % clinical score chosen in the Stats tab (BFMDRS for dystonia,
        % UHDRS for chorea).
        if strcmp(ddScore.Value, 'UHDRS')
            b = [E.uhdrs]; snm = 'UHDRS';
        else
            b = [E.bfm]; snm = 'BFMDRS';
        end
        thr = str2double(efBFM.Value);
        if isnan(thr)
            thr = median(b(~isnan(b)));
        end
        grp = nan(size(b));
        grp(b <  thr) = 1;
        grp(b >= thr) = 2;
    end

%% ================================================================ manual Timeline events
    function h = drawManEvents(ax, xl, yl, withLabels)
        % Manual events: dash-dot lines with a marker at the top; one line per
        % event so its data tip can carry the note. Legend: one entry per name.
        h = gobjects(0);
        if ~chkManEv.Value || isempty(S.manEv), return; end
        names = unique({S.manEv.name});
        cm = tcolors(numel(names) + 2);
        cm = cm(end - numel(names) + 1:end, :);          % warm end of turbo
        shown = false(1, numel(names));
        for q = 1:numel(S.manEv)
            e = S.manEv(q);
            x = datenum(localTime(e.dt));
            if x < xl(1) || x > xl(2), continue; end
            j = find(strcmp(names, e.name), 1);
            vis = 'off';
            if withLabels && ~shown(j), vis = 'on'; shown(j) = true; end
            hl = plot(ax, [x x], yl, '-.', 'Color', cm(j, :), 'LineWidth', 1.6, ...
                'Marker', 'v', 'MarkerIndices', 2, 'MarkerFaceColor', cm(j, :), 'MarkerSize', 7, ...
                'DisplayName', [e.name ' (manual)'], 'HandleVisibility', vis, ...
                'Tag', 'manEv', 'UserData', e.note);
            h(end+1) = hl; %#ok<AGROW>
            if withLabels
                text(ax, x, yl(2), ['  ' e.name], 'Rotation', 90, 'FontSize', 8, ...
                    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
                    'Color', cm(j, :) * 0.75, 'PickableParts', 'none', 'Interpreter', 'none');
            end
        end
    end

    function addManEvNotes(h)
        % Append the note to each manual event's data tip.
        for q = 1:numel(h)
            try
                if ~isempty(h(q).UserData)
                    h(q).DataTipTemplate.DataTipRows(end+1) = ...
                        dataTipTextRow('Note', repmat({h(q).UserData}, size(h(q).XData)));
                end
            catch
            end
        end
    end

    function names = manEvNameChoices()
        names = {'Programming change', 'Medication change', 'Symptom flare', 'Illness', ...
            'Sleep disruption', 'Note'};
        if ~isempty(S.events), names = [names, {S.events.name}]; end
        if ~isempty(S.manEv), names = [{S.manEv.name}, names]; end
        names = unique(names, 'stable');
    end

    function onPickToggle()
        if tglPickEv.Value
            if isempty(S.files)
                tglPickEv.Value = false;
                uialert(fig, 'Load files first.', 'Manual events'); return;
            end
            lblPickEv.Text = 'Click the Timeline plot where the event happened.';
            % the axes itself catches the click: plotted objects stop
            % intercepting it and default zoom/pan/datatip are paused
            try, disableDefaultInteractivity(axTL); catch, end
            set(findall(axTL, '-property', 'HitTest'), 'HitTest', 'off');
            axTL.HitTest = 'on';
            axTL.PickableParts = 'all';
            axTL.ButtonDownFcn = @(~,~) onAxPick();
        else
            stopPick();
        end
    end

    function stopPick()
        tglPickEv.Value = false;
        lblPickEv.Text = '';
        axTL.ButtonDownFcn = '';
        try, enableDefaultInteractivity(axTL); catch, end
        refreshTimeline();                 % restores data tips on the redrawn lines
    end

    function onAxPick()
        x = axTL.CurrentPoint(1, 1);
        stopPick();
        if x > 7e5 && x < 8e5
            openManEvDialog(x);
        end
    end

    function openManEvDialog(x)
        % x = datenum (local time) from a click, or NaN to type the time.
        if isnan(x)
            xl = axTL.XLim;
            if xl(1) > 7e5, x = mean(xl); else, x = now; end %#ok<TNOW1>
        end
        tStr = char(string(datetime(x, 'ConvertFrom', 'datenum'), 'yyyy-MM-dd HH:mm'));
        pos = fig.Position;
        d = uifigure('Name', 'Add manual event', 'WindowStyle', 'modal', ...
            'Position', [pos(1) + 120, pos(2) + 160, 460, 230]);
        gD = uigridlayout(d, [5 2]);
        gD.ColumnWidth = {110, '1x'};
        gD.RowHeight = {26, 26, 26, '1x', 32};
        uilabel(gD, 'Text', 'Event', 'HorizontalAlignment', 'right');
        ddN = uidropdown(gD, 'Items', manEvNameChoices(), 'Editable', 'on', ...
            'Tooltip', 'Pick a type or type your own');
        uilabel(gD, 'Text', sprintf('Time (%s)', tzName()), 'HorizontalAlignment', 'right');
        efT = uieditfield(gD, 'text', 'Value', tStr, 'Placeholder', 'yyyy-MM-dd HH:mm');
        uilabel(gD, 'Text', 'Note', 'HorizontalAlignment', 'right');
        efN = uieditfield(gD, 'text', 'Value', '', 'Placeholder', 'optional, e.g. L 2.5 -> 3.0 mA');
        uilabel(gD, 'Text', '');
        uilabel(gD, 'Text', '');
        uilabel(gD, 'Text', '');
        gB = uigridlayout(gD, [1 2]);
        gB.Padding = [0 0 0 0];
        uibutton(gB, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) delete(d));
        uibutton(gB, 'Text', 'Add', 'ButtonPushedFcn', @(~,~) addFromDialog());

        function addFromDialog()
            dt = parseLocalTime(efT.Value);
            nm = strtrim(char(ddN.Value));
            if isnat(dt)
                uialert(d, 'Enter the time as yyyy-MM-dd HH:mm.', 'Time'); return;
            end
            if isempty(nm)
                uialert(d, 'Give the event a name.', 'Event'); return;
            end
            S.manEv(end+1) = struct('dt', dt, 'name', nm, 'note', strtrim(char(efN.Value)));
            sortManEv();
            delete(d);
            refreshTimeline();
        end
    end

    function dt = parseLocalTime(str)
        % Local "yyyy-MM-dd HH:mm[:ss]" in the selected time zone -> UTC datetime.
        dt = natUTC();
        str = strtrim(char(str));
        fmts = {'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd'};
        for q = 1:numel(fmts)
            try
                d0 = datetime(str, 'InputFormat', fmts{q}, 'TimeZone', tzName());
                if ~isnat(d0)
                    d0.TimeZone = 'UTC';
                    dt = d0;
                    return;
                end
            catch
            end
        end
    end

    function sortManEv()
        if numel(S.manEv) > 1
            [~, o] = sort(vertcat(S.manEv.dt));
            S.manEv = S.manEv(o);
        end
    end

    function openManEvManager()
        pos = fig.Position;
        d = uifigure('Name', 'Manual events', 'WindowStyle', 'modal', ...
            'Position', [pos(1) + 100, pos(2) + 100, 720, 420]);
        gM = uigridlayout(d, [3 1]);
        gM.RowHeight = {22, '1x', 32};
        uilabel(gM, 'Text', sprintf(['Edit cells directly (time as yyyy-MM-dd HH:mm, %s). ' ...
            'Select a row to delete it.'], tzName()));
        tb = uitable(gM, 'RowName', {}, 'ColumnEditable', [true true true], ...
            'CellEditCallback', @(~,evt) onEdit(evt), ...
            'CellSelectionCallback', @(~,evt) onSel(evt));
        gB = uigridlayout(gM, [1 5]);
        gB.Padding = [0 0 0 0];
        gB.ColumnWidth = {110, 110, 110, '1x', 90};
        uibutton(gB, 'Text', 'Delete selected', 'ButtonPushedFcn', @(~,~) onDelete());
        uibutton(gB, 'Text', 'Import CSV...', 'ButtonPushedFcn', @(~,~) onImport());
        uibutton(gB, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) onExport());
        uilabel(gB, 'Text', '');
        uibutton(gB, 'Text', 'Close', 'ButtonPushedFcn', @(~,~) delete(d));
        selRow = [];
        fillTable();

        function fillTable()
            n = numel(S.manEv);
            if n == 0
                tb.Data = table(cell(0, 1), cell(0, 1), cell(0, 1), ...
                    'VariableNames', {'Time', 'Event', 'Note'});
                return;
            end
            tl = cellstr(string(localTime(vertcat(S.manEv.dt)), 'yyyy-MM-dd HH:mm'));
            tb.Data = table(tl, {S.manEv.name}', {S.manEv.note}', ...
                'VariableNames', {'Time', 'Event', 'Note'});
        end

        function onSel(evt)
            if isempty(evt.Indices), selRow = []; else, selRow = unique(evt.Indices(:, 1)); end
        end

        function onEdit(evt)
            r = evt.Indices(1); c = evt.Indices(2);
            if r > numel(S.manEv), return; end
            v = strtrim(char(evt.NewData));
            switch c
                case 1
                    dt = parseLocalTime(v);
                    if isnat(dt)
                        uialert(d, 'Use yyyy-MM-dd HH:mm.', 'Time');
                        fillTable(); return;
                    end
                    S.manEv(r).dt = dt;
                    sortManEv();
                case 2
                    if isempty(v), fillTable(); return; end
                    S.manEv(r).name = v;
                otherwise
                    S.manEv(r).note = v;
            end
            fillTable();
            refreshTimeline();
        end

        function onDelete()
            if isempty(selRow), uialert(d, 'Select a row first.', 'Delete'); return; end
            S.manEv(selRow(selRow <= numel(S.manEv))) = [];
            selRow = [];
            fillTable();
            refreshTimeline();
        end

        function onExport()
            if isempty(S.manEv), uialert(d, 'No manual events to export.', 'Export'); return; end
            [f, p] = uiputfile('*.csv', 'Export manual events', 'manual_events.csv');
            figure(d);
            if isequal(f, 0), return; end
            T = table(cellstr(string(vertcat(S.manEv.dt), 'yyyy-MM-dd''T''HH:mm:ss''Z''')), ...
                {S.manEv.name}', {S.manEv.note}', 'VariableNames', {'TimeUTC', 'Event', 'Note'});
            writetable(T, fullfile(p, f));
        end

        function onImport()
            [f, p] = uigetfile('*.csv', 'Import manual events');
            figure(d);
            if isequal(f, 0), return; end
            try
                T = readtable(fullfile(p, f), 'TextType', 'char', 'Delimiter', ',', ...
                    'DatetimeType', 'text');
                added = 0;
                for q = 1:height(T)
                    dt = parsePerceptTime(string(T.TimeUTC(q)));
                    if isnat(dt), continue; end
                    nt = '';
                    if ismember('Note', T.Properties.VariableNames) && iscell(T.Note) && ~isempty(T.Note{q})
                        nt = char(T.Note{q});
                    end
                    S.manEv(end+1) = struct('dt', dt, 'name', char(T.Event{q}), 'note', nt);
                    added = added + 1;
                end
                sortManEv();
                fillTable();
                refreshTimeline();
                uialert(d, sprintf('Imported %d event(s).', added), 'Import', 'Icon', 'success');
            catch ME
                uialert(d, ['Could not read the file: ' ME.message], 'Import');
            end
        end
    end

%% ================================================================ Timeline tab
    function refreshTimelineTab()
        refreshTimeline();
        refreshCirc();
    end

    function refreshTimeline()
        clearAxes(axTL); legend(axTL, 'off');
        hold(axTL, 'on');
        hs = selHemis();
        allX = [];
        for i = 1:numel(hs)
            h = hs{i};
            [dt, v] = getTLsel(h);
            if isempty(v), continue; end
            c = hcol(h);
            x = datenum(dt);
            [xg, vg] = insertGaps(x, v, 30/1440);
            plot(axTL, xg, vg, '-', 'Color', c + (1 - c) * 0.6, 'LineWidth', 0.5, ...
                'HandleVisibility', 'off');
            vm = movmedian(v, 144, 'omitnan');
            [xg, vg] = insertGaps(x, vm, 30/1440);
            plot(axTL, xg, vg, '-', 'Color', c, 'LineWidth', 1.6, ...
                'DisplayName', [hemiName(h) ' (24-h moving median)']);
            allX = [allX; x]; %#ok<AGROW>
        end
        if isempty(allX)
            title(axTL, 'No Timeline data in the ticked sessions');
            hold(axTL, 'off');
            refreshStim([]);
            return;
        end
        axTL.YScale = ternary(chkLog.Value, 'log', 'linear');
        xl = [min(allX) max(allX)];
        if xl(2) <= xl(1), xl = xl + [-0.5 0.5]; end
        xlim(axTL, xl);
        yl = axTL.YLim;
        ylim(axTL, yl);

        if chkEpochs.Value
            E = getEpochs();
            for k = selEpochs()
                x1 = max(datenum(localTime(E(k).tStart)), xl(1));
                x2 = min(datenum(localTime(E(k).tEnd)), xl(2));
                if isnan(x1) || isnan(x2) || x2 <= x1, continue; end
                if mod(k, 2) == 0
                    toBack(patch(axTL, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], [0.5 0.5 0.5], ...
                        'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off'));
                end
                plot(axTL, [x2 x2], yl, '--', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
                text(axTL, (x1 + x2) / 2, yl(2), E(k).label, 'VerticalAlignment', 'top', ...
                    'HorizontalAlignment', 'center', 'FontSize', 9, 'Interpreter', 'none');
            end
        end

        if chkEvents.Value && ~isempty(S.events)
            idx = eventFilter();
            names = unique({S.events(idx).name});
            cmap = tcolors(max(numel(names), 1));
            for j = 1:numel(names)
                sel = idx(strcmp({S.events(idx).name}, names{j}));
                xe = datenum(localTime(vertcat(S.events(sel).dt)));
                xe = xe(xe >= xl(1) & xe <= xl(2));
                if isempty(xe), continue; end
                X = [xe(:)'; xe(:)'; nan(1, numel(xe))];
                Y = repmat([yl(1); yl(2); NaN], 1, numel(xe));
                plot(axTL, X(:), Y(:), ':', 'Color', cmap(j, :), 'LineWidth', 1.1, ...
                    'DisplayName', names{j});
            end
        end
        manH = drawManEvents(axTL, xl, yl, true);
        hold(axTL, 'off');
        setDateTicks(axTL);
        ylabel(axTL, 'LFP power (a.u.)');
        ids = unique({S.files.patientId});
        ids = ids(~cellfun(@isempty, ids));
        title(axTL, sprintf('BrainSense Timeline  %s  (%s)', strjoin(ids, ', '), tzName()), ...
            'Interpreter', 'none');
        legend(axTL, 'Location', 'northeastoutside', 'Interpreter', 'none', 'Box', 'off');
        tipAxes(axTL);
        addManEvNotes(manH);
        refreshStim(xl);
    end

    function refreshStim(xl)
        clearAxes(axStim); legend(axStim, 'off');
        if isempty(xl)
            title(axStim, '');
            return;
        end
        hold(axStim, 'on');
        hs = selHemis();
        top = 0; nChg = 0;
        for i = 1:numel(hs)
            h = hs{i};
            T = S.tl.(h);
            if isempty(T.amp) || all(isnan(T.amp)), continue; end
            keepS = ismember(assignEpoch(T.dt, getEpochs()), selEpochs());
            T.dt = T.dt(keepS); T.amp = T.amp(keepS);
            if isempty(T.amp), continue; end
            x = datenum(localTime(T.dt));
            [xg, ag] = insertGaps(x, T.amp, 30/1440);
            stairs(axStim, xg, ag, '-', 'Color', hcol(h), 'LineWidth', 1.4, ...
                'DisplayName', hemiName(h));
            a = T.amp(~isnan(T.amp));
            nChg = nChg + sum(abs(diff(a)) > 0.05);
            top = max(top, max(a));
        end
        if top > 0
            drawManEvents(axStim, xl, [0 max(top * 1.15, 0.5)], false);
        end
        hold(axStim, 'off');
        xlim(axStim, xl);
        ylim(axStim, [0 max(top * 1.15, 0.5)]);
        setDateTicks(axStim);
        ylabel(axStim, 'Stim (mA)');
        title(axStim, sprintf('Stimulation amplitude from Timeline: %d change(s) > 0.05 mA', nChg), ...
            'FontWeight', 'normal', 'FontSize', 10);
        legend(axStim, 'Location', 'northeastoutside', 'Box', 'off');
        tipAxes(axStim);
    end

    function refreshCirc()
        clearAxes(axCirc); legend(axCirc, 'off');
        hold(axCirc, 'on');
        hs = selHemis();
        ctr = ((0:143)' + 0.5) / 6;            % bin centres, hours
        styles = {'-', '--'};
        mode = ddProfile.Value;
        E = getEpochs();
        drew = false;
        extra = '';
        for i = 1:numel(hs)
            h = hs{i};
            [dt, v, dtU] = getTLsel(h);
            if isempty(v), continue; end
            bin = floor((hour(dt) * 60 + minute(dt)) / 10) + 1;
            ok = ~isnan(v);
            ls = styles{i};
            switch mode
                case 'All data'
                    [m, q1, q3] = binStats(bin(ok), v(ok));
                    c = hcol(h);
                    plot(axCirc, ctr, m, ls, 'Color', c, 'LineWidth', 1.6, ...
                        'DisplayName', [hemiName(h) ' median']);
                    plot(axCirc, ctr, q1, ':', 'Color', c, 'HandleVisibility', 'off');
                    plot(axCirc, ctr, q3, ':', 'Color', c, 'HandleVisibility', 'off');
                    drew = true;
                    extra = ' (dotted = IQR)';
                case 'By score group'
                    [grp, thr, snm] = bfmGroups(E);
                    ep = assignEpoch(dtU, E);
                    g = nan(size(ep));
                    okE = ~isnan(ep);
                    gg = grp(:);
                    g(okE) = gg(ep(okE));
                    cols  = num2cell(tcolors(2), 2);
                    gname = {sprintf('%s < %g', snm, thr), sprintf('%s >= %g', snm, thr)};
                    for q = 1:2
                        sel = ok & g == q;
                        if ~any(sel), continue; end
                        [m, q1, q3] = binStats(bin(sel), v(sel));
                        nDays = numel(unique(dateshift(dt(sel), 'start', 'day')));
                        plot(axCirc, ctr, m, ls, 'Color', cols{q}, 'LineWidth', 1.6, ...
                            'DisplayName', sprintf('%s, %s (%d days)', hemiName(h), gname{q}, nDays));
                        plot(axCirc, ctr, q1, ':', 'Color', cols{q}, 'HandleVisibility', 'off');
                        plot(axCirc, ctr, q3, ':', 'Color', cols{q}, 'HandleVisibility', 'off');
                        drew = true;
                    end
                    extra = ' (dotted = IQR)';
                case 'By epoch'
                    ep = assignEpoch(dtU, E);
                    cmap = tcolors(numel(E));
                    for k = selEpochs()
                        sel = ok & ep == k;
                        if ~any(sel), continue; end
                        m = binStats(bin(sel), v(sel));
                        plot(axCirc, ctr, m, ls, 'Color', cmap(k, :), 'LineWidth', 1.3, ...
                            'DisplayName', sprintf('%s %s', E(k).label, hemiName(h)));
                        drew = true;
                    end
            end
        end
        hold(axCirc, 'off');
        if ~drew
            title(axCirc, '24-h profile: no data');
            return;
        end
        axCirc.YScale = ternary(chkLog.Value, 'log', 'linear');
        xlim(axCirc, [0 24]);
        axCirc.XTick = 0:3:24;
        xlabel(axCirc, sprintf('Hour of day (%s)', tzName()), 'Interpreter', 'none');
        ylabel(axCirc, 'LFP power (a.u.)');
        title(axCirc, ['24-h profile, 10-min bins, ' lower(mode) extra]);
        legend(axCirc, 'Location', 'northeastoutside', 'Interpreter', 'none', 'Box', 'off');
        tipAxes(axCirc);
    end

%% ================================================================ Events tab
    function idx = eventFilter()
        % Events in the ticked sessions, limited to the selected event types.
        idx = 1:numel(S.events);
        if isempty(idx), return; end
        ep = assignEpoch(vertcat(S.events.dt), getEpochs());
        idx = idx(ismember(ep(:)', selEpochs()));
        types = lbEvTypes.Value;
        if ischar(types), types = {types}; end
        if ~isempty(types) && ~isempty(idx)
            idx = idx(ismember({S.events(idx).name}, types));
        end
    end

    function refreshEventsTab()
        if numel(S.evChecked) ~= numel(S.events)
            S.evChecked = false(numel(S.events), 1);
        end
        types = {};
        if ~isempty(S.events)
            ep = assignEpoch(vertcat(S.events.dt), getEpochs());
            inSel = ismember(ep, selEpochs());
            if any(inSel), types = unique({S.events(inSel).name}); end
        end
        prev = lbEvTypes.Value;
        if ischar(prev), prev = {prev}; end
        lbEvTypes.Items = types;
        if ~isempty(types)
            lbEvTypes.Value = prev(ismember(prev, types));
        end
        refreshEventsTable();
        clearAxes(axEvSel); legend(axEvSel, 'off');
        title(axEvSel, 'Click an event row to see its spectra');
    end

    function onEvTypeChange()
        refreshEventsTable();
        refreshTimeline();
    end

    function refreshEventsTable()
        idx = eventFilter();
        S.evView = idx;
        if isempty(idx)
            tblEv.Data = table();
            return;
        end
        ev = S.events(idx);
        E = getEpochs();
        ep = assignEpoch(vertcat(ev.dt), E);
        sess = repmat({'?'}, numel(idx), 1);
        for q = 1:numel(idx)
            if ~isnan(ep(q)), sess{q} = E(ep(q)).label; end
        end
        dts = localTime(vertcat(ev.dt));
        hasL = ~cellfun(@isempty, {ev.pL})';
        hasR = ~cellfun(@isempty, {ev.pR})';
        tblEv.Data = table(S.evChecked(idx), cellstr(string(dts, 'yyyy-MM-dd HH:mm')), {ev.name}', ...
            sess, hasL, hasR, 'VariableNames', {'Use', 'Time', 'Event', 'Session', 'L_spec', 'R_spec'});
    end

    function onEvEdit(evt)
        r = evt.Indices(1);
        if r > numel(S.evView), return; end
        S.evChecked(S.evView(r)) = logical(evt.NewData);
    end

    function onEvClearChecks()
        S.evChecked(:) = false;
        refreshEventsTable();
    end

    function onEvSelect(evt)
        if isempty(evt.Indices) || isempty(S.evView), return; end
        r = evt.Indices(1, 1);
        if r > numel(S.evView), return; end
        e = S.events(S.evView(r));
        clearAxes(axEvSel); legend(axEvSel, 'off');
        hold(axEvSel, 'on');
        any_ = false;
        if ~isempty(e.pL)
            plot(axEvSel, e.fL, e.pL, '-', 'Color', hcol('L'), 'LineWidth', 1.5, 'DisplayName', 'Left');
            any_ = true;
        end
        if ~isempty(e.pR)
            plot(axEvSel, e.fR, e.pR, '-', 'Color', hcol('R'), 'LineWidth', 1.5, 'DisplayName', 'Right');
            any_ = true;
        end
        if any_
            shadeBand(axEvSel, efBetaLo.Value, efBetaHi.Value);
            legend(axEvSel, 'Box', 'off');
        end
        hold(axEvSel, 'off');
        xlabel(axEvSel, 'Frequency (Hz)'); ylabel(axEvSel, 'Power (a.u.)');
        ttl = sprintf('%s  %s', e.name, char(string(localTime(e.dt), 'yyyy-MM-dd HH:mm')));
        if ~any_, ttl = [ttl '  (no snapshot spectrum)']; end
        title(axEvSel, ttl, 'Interpreter', 'none');
        tipAxes(axEvSel);
    end

    function onEvCompare()
        idx = S.evView;
        if isempty(idx)
            uialert(fig, 'No events in the ticked sessions / selected types.', 'Events'); return;
        end
        mode = ddEvGroup.Value;
        if startsWith(mode, 'Checked')
            idx = idx(S.evChecked(idx));
            if isempty(idx)
                uialert(fig, 'Tick events in the Use column first.', 'Events'); return;
            end
        end
        E = getEpochs();
        ep = assignEpoch(vertcat(S.events(idx).dt), E);
        names = {S.events(idx).name};
        key = names;
        if strcmp(mode, 'Event type x session')
            for q = 1:numel(idx)
                if ~isnan(ep(q)), key{q} = sprintf('%s | %s', names{q}, E(ep(q)).label); end
            end
        elseif strcmp(mode, 'Checked events: individual')
            for q = 1:numel(idx)
                key{q} = sprintf('%s %s', names{q}, ...
                    char(string(localTime(S.events(idx(q)).dt), 'yyyy-MM-dd HH:mm')));
            end
        end
        [groups, ~, gi] = unique(key, 'stable');
        band = [efBetaLo.Value efBetaHi.Value];
        cmap = tcolors(max(numel(groups), 1));
        txt = {sprintf('Grouping: %s | beta band %g-%g Hz', mode, band)};
        hc = {'L', 'R'}; axs = {axEvL, axEvR};
        for a = 1:2
            h = hc{a}; ax = axs{a};
            fF = ['f' h]; pF = ['p' h];
            clearAxes(ax); legend(ax, 'off'); hold(ax, 'on');
            bp = cell(1, numel(groups));
            fref = [];
            for g = 1:numel(groups)
                mem = idx(gi == g);
                mem = mem(~cellfun(@isempty, {S.events(mem).(pF)}));
                if isempty(mem), continue; end
                if isempty(fref), fref = S.events(mem(1)).(fF); end
                M = nan(numel(mem), numel(fref));
                for j = 1:numel(mem)
                    M(j, :) = interp1(S.events(mem(j)).(fF), S.events(mem(j)).(pF), fref, 'linear', NaN);
                end
                med = median(M, 1, 'omitnan');
                plot(ax, fref, med, '-', 'Color', cmap(g, :), 'LineWidth', 1.6, ...
                    'DisplayName', sprintf('%s (n=%d)', groups{g}, numel(mem)));
                if numel(mem) > 2
                    q1 = zeros(size(med)); q3 = q1;
                    for c = 1:numel(fref)
                        qq = pctl(M(:, c), [25 75]);
                        q1(c) = qq(1); q3(c) = qq(2);
                    end
                    plot(ax, fref, q1, ':', 'Color', cmap(g, :), 'HandleVisibility', 'off');
                    plot(ax, fref, q3, ':', 'Color', cmap(g, :), 'HandleVisibility', 'off');
                end
                inB = fref >= band(1) & fref <= band(2);
                bp{g} = mean(M(:, inB), 2, 'omitnan');
            end
            ok = ~cellfun(@isempty, bp);
            if any(ok)
                shadeBand(ax, band(1), band(2));
                legend(ax, 'Location', 'northeast', 'Interpreter', 'none', 'Box', 'off', 'FontSize', 8);
            end
            hold(ax, 'off');
            xlabel(ax, 'Frequency (Hz)'); ylabel(ax, 'Power (a.u.)');
            title(ax, sprintf('%s: median snapshot spectra (dotted = IQR)', hemiName(h)));
            txt{end+1, 1} = ''; %#ok<AGROW>
            txt{end+1, 1} = sprintf('--- %s: mean beta power per event ---', hemiName(h)); %#ok<AGROW>
            for g = find(ok)
                q = pctl(bp{g}, [25 50 75]);
                txt{end+1, 1} = sprintf('  %-30s n=%3d  median %.3g  IQR [%.3g, %.3g]', ...
                    groups{g}, numel(bp{g}), q(2), q(1), q(3)); %#ok<AGROW>
            end
            G = bp(ok); Gl = groups(ok);
            if numel(G) >= 2 && all(cellfun(@numel, G) >= 2)
                if numel(G) == 2
                    R = mannWhitney(G{2}, G{1});
                    txt{end+1, 1} = sprintf('  Mann-Whitney: U = %.1f, z = %.2f, p = %s; Cliff''s delta = %.2f (%s)', ...
                        R.U, R.z, fmtP(R.p), R.delta, cliffLabel(R.delta)); %#ok<AGROW>
                else
                    KW = kruskalWallis(G);
                    txt{end+1, 1} = sprintf('  Kruskal-Wallis H(%d) = %.2f, p = %s', KW.df, KW.H, fmtP(KW.p)); %#ok<AGROW>
                    D = dunnHolm(G);
                    for r = 1:size(D, 1)
                        txt{end+1, 1} = sprintf('    %s vs %s: p_Holm = %s', Gl{D(r, 1)}, Gl{D(r, 2)}, fmtP(D(r, 5))); %#ok<AGROW>
                    end
                end
            end
        end
        taEv.Value = txt;
        tipAxes([axEvL axEvR]);
    end

%% ================================================================ Streaming tab
    function refreshStreamList()
        vis = [];
        if ~isempty(S.streams)
            vis = find(ismember([S.streams.fileIdx], selFiles()));
        end
        prev = ddStream.Value;
        ddStream.ItemsData = [];
        if isempty(vis)
            ddStream.Items = {'(no streaming recordings in ticked sessions)'};
            ddStream.ItemsData = 0;
            onStreamSelect();
            return;
        end
        items = cell(1, numel(vis));
        for q = 1:numel(vis)
            s = S.streams(vis(q));
            items{q} = sprintf('%s | %s | %s | %s | %.0f s', sessLabel(s.fileIdx), s.source, s.channel, ...
                char(string(localTime(s.t0), 'yyyy-MM-dd HH:mm')), numel(s.x) / s.fs);
        end
        ddStream.Items = items;
        ddStream.ItemsData = vis;
        if isnumeric(prev) && any(vis == prev), ddStream.Value = prev; end
        onStreamSelect();
    end

    function [x, fs, s] = getStreamSignal()
        x = []; fs = []; s = [];
        i = ddStream.Value;
        if isempty(S.streams) || isequal(i, 0)
            uialert(fig, 'No streaming recordings loaded.', 'Streaming');
            return;
        end
        s = S.streams(i);
        fs = s.fs;
        x = s.x(:);
        x(isnan(x)) = 0;
        x = detrend(x);
        if numel(x) < 5 * fs
            uialert(fig, 'Recording is shorter than 5 s.', 'Streaming');
            x = [];
        end
    end

    function onAnalyze()
        [x, fs, s] = getStreamSignal();
        if isempty(x), return; end
        band  = [efBetaLo.Value efBetaHi.Value];
        phB   = [efPhLo.Value efPhHi.Value];
        amB   = [efAmLo.Value efAmHi.Value];
        nyq = fs / 2;
        if band(1) >= band(2) || phB(1) >= phB(2) || amB(1) >= amB(2)
            uialert(fig, 'Each band needs low < high.', 'Parameters'); return;
        end
        if max([band(2) phB(2) amB(2)]) >= nyq - 1
            uialert(fig, sprintf('Bands must stay below Nyquist (%g Hz).', nyq), 'Parameters'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Analyzing', 'Indeterminate', 'on');
        cleaner = onCleanup(@() close(dlg));
        win  = efWin.Value;
        fmax = min(100, nyq);

        % ---- spectrogram
        [P, f, t] = stftPower(x, fs, win, 0.9);
        kf = f <= fmax;
        SdB = 10 * log10(P(kf, :) + eps);
        clearAxes(axSpec);
        imagesc(axSpec, t, f(kf), SdB);
        axSpec.YDir = 'normal';
        cl = pctl(SdB(:), [2 99.5]);
        if cl(2) > cl(1), axSpec.CLim = cl; end
        colormap(axSpec, turbo);
        colorbar(axSpec);
        hold(axSpec, 'on');
        plot(axSpec, t([1 end]), band([1 1]), 'w--', t([1 end]), band([2 2]), 'w--');
        hold(axSpec, 'off');
        axis(axSpec, 'tight');
        xlabel(axSpec, 'Time (s)'); ylabel(axSpec, 'Frequency (Hz)');
        iSt = ddStream.Value;
        [scB, scU, scSrc] = streamScore(iSt);
        title(axSpec, sprintf('Spectrogram (dB)  %s  %s  |  %s', s.source, s.channel, scoreText(scB, scU)), ...
            'Interpreter', 'none');
        inBst = f >= band(1) & f <= band(2);
        S.stLast = struct('idx', iSt, 't', t(:)', 'beta', mean(P(inBst, :), 1));

        % ---- Welch PSD
        [Pw, fw] = welchPSD(x, fs, max(win, 1));
        kw = fw >= 1 & fw <= fmax;
        clearAxes(axPSD); legend(axPSD, 'off');
        plot(axPSD, fw(kw), Pw(kw), 'k-', 'LineWidth', 1.2, 'DisplayName', 'Welch PSD');
        axPSD.YScale = 'log';
        hold(axPSD, 'on');
        shadeBand(axPSD, band(1), band(2));
        inB = fw >= band(1) & fw <= band(2);
        fb = fw(inB); pb = Pw(inB);
        [pk, j] = max(pb);
        peakF = fb(j);
        plot(axPSD, peakF, pk, 'rv', 'MarkerFaceColor', 'r', 'DisplayName', sprintf('Peak %.1f Hz', peakF));
        if ~isnan(s.foi)
            yl = axPSD.YLim;
            plot(axPSD, [s.foi s.foi], yl, 'b:', 'LineWidth', 1.2, ...
                'DisplayName', sprintf('Device FOI %g Hz', s.foi));
        end
        hold(axPSD, 'off');
        xlabel(axPSD, 'Frequency (Hz)'); ylabel(axPSD, 'PSD (a.u.^2/Hz)');
        legend(axPSD, 'Box', 'off');
        title(axPSD, 'Welch PSD (50% overlap, Hann)');
        relPow = 100 * sum(Pw(inB)) / sum(Pw(kw));

        % ---- beta bursts
        B = betaBursts(x, fs, band, efThr.Value, efMinDur.Value);
        tt = (0:numel(x) - 1)' / fs;
        clearAxes(axBurst); legend(axBurst, 'off');
        plot(axBurst, tt, B.xf, 'Color', [0.78 0.78 0.78], 'DisplayName', 'Band-passed');
        hold(axBurst, 'on');
        plot(axBurst, tt, B.env, 'Color', hcolSafe(s.hemi), 'LineWidth', 1.1, 'DisplayName', 'Envelope (200 ms)');
        plot(axBurst, tt([1 end]), [B.thr B.thr], 'r--', 'DisplayName', sprintf('%g th pctl', efThr.Value));
        yl = axBurst.YLim; ylim(axBurst, yl);
        if ~isempty(B.s)
            Xp = [tt(B.s) tt(B.e) tt(B.e) tt(B.s)]';
            Yp = repmat([yl(1); yl(1); yl(2); yl(2)], 1, numel(B.s));
            toBack(patch(axBurst, Xp, Yp, [1 0.75 0.1], 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
                'DisplayName', 'Bursts'));
        end
        hold(axBurst, 'off');
        xlim(axBurst, tt([1 end]));
        xlabel(axBurst, 'Time (s)'); ylabel(axBurst, 'Amplitude (a.u.)');
        title(axBurst, sprintf('Beta bursts %g-%g Hz (n = %d)', band, numel(B.s)));
        legend(axBurst, 'Box', 'off', 'Location', 'northeast');

        % ---- PAC
        R = pacAnalysis(x, fs, phB, amB, 200);
        colorbar(axPAC, 'off');
        clearAxes(axPAC); legend(axPAC, 'off');
        ctrDeg = rad2deg(R.centers);
        bar(axPAC, [ctrDeg ctrDeg + 360], [R.pdist; R.pdist], 1, 'FaceColor', hcolSafe(s.hemi), ...
            'EdgeColor', 'none');
        axPAC.YDir = 'normal';
        xlim(axPAC, [-180 540]);
        axPAC.XTick = -180:180:540;
        xlabel(axPAC, sprintf('Phase of %g-%g Hz (deg)', phB));
        ylabel(axPAC, sprintf('Norm. %g-%g Hz amplitude', amB));
        title(axPAC, sprintf('PAC: MI = %.2e, z = %.2f', R.MI, R.z));

        % ---- text summary
        txt = {
            sprintf('File     : %s', s.file)
            sprintf('Channel  : %s (%s)', s.channel, s.source)
            sprintf('Severity : %s (%s)', scoreText(scB, scU), scSrc)
            sprintf('Stim     : L %s mA, R %s mA (median)', num2s(stimMedian(iSt, 'L')), num2s(stimMedian(iSt, 'R')))
            sprintf('fs = %g Hz, duration = %.1f s', fs, numel(x) / fs)
            sprintf('Peak in %g-%g Hz: %.1f Hz', band, peakF)
            sprintf('Band power / 1-%g Hz: %.1f %%', fmax, relPow)
            ''
            sprintf('BETA BURSTS (env > %g th pctl, >= %g ms)', efThr.Value, efMinDur.Value)
            sprintf('  n        : %d', numel(B.s))
            sprintf('  rate     : %.1f /min', B.rate)
            sprintf('  duration : mean %.0f ms, median %.0f ms', mean(B.dur), median(B.dur))
            sprintf('  >400 ms  : %.0f %% of bursts', 100 * mean(B.dur > 400))
            sprintf('  in burst : %.1f %% of time', B.pctTime)
            sprintf('  peak amp : mean %.3g', mean(B.amp))
            ''
            'PAC (Tort MI, 18 bins, 200 surrogates)'
            sprintf('  phase %g-%g Hz, amp %g-%g Hz', phB, amB)
            sprintf('  MI = %.3e', R.MI)
            sprintf('  z  = %.2f, p = %s', R.z, fmtP(R.p))
            ''
            'Edges (1 s each side) are excluded from'
            'burst and PAC metrics. Stim-on recordings'
            'carry stimulation artifact/harmonics:'
            'treat high-frequency power and PAC there'
            'with caution.'};
        taStream.Value = txt;
        plotStreamStim();
        refreshSegTable();
        tipAxes([axPSD axBurst]);
        tipAxes(axSpec, 'Power (dB)');
    end

    function onComod()
        [x, fs] = getStreamSignal();
        if isempty(x), return; end
        phC = 4:2:30;
        amC = 40:5:min(115, fs / 2 - 12);
        if isempty(amC)
            uialert(fig, 'Sampling rate too low for an amplitude axis >= 40 Hz.', 'Comodulogram'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Comodulogram', 'Value', 0);
        n = numel(x);
        edge = round(fs);
        keep = (edge + 1):(n - edge);
        nb = 18;
        A = zeros(numel(keep), numel(amC));
        for j = 1:numel(amC)
            a = abs(analyticSignal(fftBandpass(x, fs, amC(j) - 10, amC(j) + 10)));
            A(:, j) = a(keep);
            dlg.Value = 0.5 * j / numel(amC);
        end
        MI = zeros(numel(phC), numel(amC));
        for i = 1:numel(phC)
            ph = angle(analyticSignal(fftBandpass(x, fs, phC(i) - 1, phC(i) + 1)));
            b = phaseBins(ph(keep), nb);
            for j = 1:numel(amC)
                MI(i, j) = tortMI(b, A(:, j), nb);
            end
            dlg.Value = 0.5 + 0.5 * i / numel(phC);
        end
        close(dlg);
        clearAxes(axPAC); legend(axPAC, 'off');
        imagesc(axPAC, phC, amC, MI');
        axPAC.YDir = 'normal';
        axis(axPAC, 'tight');
        colormap(axPAC, turbo);
        colorbar(axPAC);
        xlabel(axPAC, 'Phase frequency (Hz, 2-Hz bands)');
        ylabel(axPAC, 'Amplitude frequency (Hz, 20-Hz bands)');
        title(axPAC, 'Tort MI comodulogram (raw MI, no surrogates)');
        tipAxes(axPAC, 'Modulation index');
    end

%% ================================================================ shared session helpers
    function [items, data] = sessionItems(fis)
        % Dropdown items for a set of file indices, in chronological order.
        E = getEpochs();
        fis = unique(fis(~isnan(fis)));
        ks = zeros(size(fis));
        for q = 1:numel(fis)
            ks(q) = find([E.fileIdx] == fis(q), 1);
        end
        [ks, o] = sort(ks);
        fis = fis(o);
        items = cell(1, numel(fis));
        for q = 1:numel(fis)
            items{q} = sprintf('%s  %s', E(ks(q)).label, S.files(fis(q)).name);
        end
        data = fis(:)';
    end

    function lbl = sessLabel(fi)
        E = getEpochs();
        k = find([E.fileIdx] == fi, 1);
        if isempty(k), lbl = '?'; else, lbl = E(k).label; end
    end

    function setDropdown(dd, items, data, emptyText)
        prev = dd.Value;
        dd.ItemsData = [];
        if isempty(items)
            dd.Items = {emptyText};
            dd.ItemsData = 0;
            return;
        end
        dd.Items = items;
        dd.ItemsData = data(:)';
        if isnumeric(prev) && isscalar(prev) && any(data == prev)
            dd.Value = prev;
        end
    end

%% ================================================================ Timeline 3D tab
    function [Z, days] = t3Matrix(dt, v)
        % Day x 10-min-bin matrix (median per cell), continuous day axis.
        ok = ~isnan(v);
        dt = dt(ok); v = v(ok);
        if isempty(v), Z = []; days = []; return; end
        dn = floor(datenum(dt));
        days = (min(dn):max(dn))';
        ri = dn - days(1) + 1;
        ci = floor((hour(dt) * 60 + minute(dt)) / 10) + 1;
        Z = accumarray([ri(:) ci(:)], v(:), [numel(days) 144], @median, NaN);
    end

    function Z = t3Clean(Z)
        % Transform, optional gap fill, optional 2-D median smoothing.
        switch ddT3Z.Value
            case 'Power'
            otherwise
                Z(Z <= 0) = NaN;
                Z = log10(Z);
        end
        holes = isnan(Z);
        if chkT3Fill.Value
            try
                Z = fillmissing(Z, 'linear', 2, 'EndValues', 'none', 'MaxGap', 3);
            catch
            end
        end
        k = 0;
        if startsWith(ddT3Smooth.Value, '3'), k = 3; elseif startsWith(ddT3Smooth.Value, '5'), k = 5; end
        if k > 0
            filled = ~isnan(Z);
            Z = movmedian(movmedian(Z, k, 2, 'omitnan'), k, 1, 'omitnan');
            Z(~filled) = NaN;              % smoothing never invents data in real gaps
        end
        if startsWith(ddT3Z.Value, 'z-score')
            mu = mean(Z(:), 'omitnan'); sd = std(Z(:), 'omitnan');
            if sd > 0, Z = (Z - mu) / sd; end
        end
        if ~chkT3Fill.Value, Z(holes) = NaN; end
    end

    function onT3Plot()
        E = getEpochs();
        ks = selEpochs();
        if isempty(ks)
            uialert(fig, 'Tick at least one session in the left panel.', 'Timeline 3D'); return;
        end
        mode = ddT3Layout.Value;
        stacked = startsWith(mode, 'Sessions stacked');
        if startsWith(mode, 'Single')
            groups = {ks}; glabels = {'All ticked sessions'};
        else
            groups = num2cell(ks); glabels = {E(ks).label};
        end
        hc = {'L', 'R'};
        TL = cell(1, 2);
        for a = 1:2
            [dt, v, ~, ep] = getTLsel(hc{a});
            TL{a} = struct('dt', dt, 'v', v, 'ep', ep);
        end
        panels = struct('Z', {}, 'days', {}, 'ttl', {}, 'row', {}, 'col', {});
        for g = 1:numel(groups)
            for a = 1:2
                sel = ismember(TL{a}.ep, groups{g});
                [Z, days] = t3Matrix(TL{a}.dt(sel), TL{a}.v(sel));
                if ~isempty(Z), Z = t3Clean(Z); end
                if stacked, rr = g; cc = a; else, rr = a; cc = g; end
                panels(end+1) = struct('Z', Z, 'days', days, ...
                    'ttl', sprintf('%s | %s', glabels{g}, hemiName(hc{a})), 'row', rr, 'col', cc); %#ok<AGROW>
            end
        end
        allZ = [];
        for p = 1:numel(panels), allZ = [allZ; panels(p).Z(isfinite(panels(p).Z))]; end %#ok<AGROW>
        lim = pctl(allZ, [1 99]);
        nR = max([panels.row]); nC = max([panels.col]);
        delete(gT3.Children);
        if stacked && nR > 2
            gT3.RowHeight = repmat({330}, 1, nR);     % fixed height -> scroll bar
        else
            gT3.RowHeight = repmat({'1x'}, 1, nR);
        end
        if ~stacked && nC > 4
            gT3.ColumnWidth = repmat({300}, 1, nC);   % fixed width -> scroll bar
        else
            gT3.ColumnWidth = repmat({'1x'}, 1, nC);
        end
        ctr = ((0:143) + 0.5) / 6;
        switch ddT3Z.Value
            case 'Power', zlab = 'Power (a.u.)';
            case 'log10 power', zlab = 'log_{10} power';
            otherwise, zlab = 'z (log_{10} power)';
        end
        topDown = startsWith(ddT3View.Value, 'Top');
        axs = gobjects(0);
        for p = 1:numel(panels)
            P = panels(p);
            ax = uiaxes(gT3);
            ax.Layout.Row = P.row;
            ax.Layout.Column = P.col;
            if isempty(P.Z) || all(isnan(P.Z(:)))
                title(ax, [P.ttl ': no data'], 'Interpreter', 'none', 'FontSize', 9);
                continue;
            end
            axs(end+1) = ax; %#ok<AGROW>
            Z = P.Z; days = P.days;
            if size(Z, 1) < 2, Z = [Z; Z]; days = [days; days + 1]; end %#ok<AGROW>
            surf(ax, ctr, days, Z, 'EdgeColor', 'none');
            colormap(ax, turbo);
            if topDown, view(ax, 0, 90); else, view(ax, -35, 40); end
            xlim(ax, [0 24]); ax.XTick = 0:6:24;
            ylim(ax, days([1 end]));
            yt = unique(round(linspace(days(1), days(end), min(5, numel(days)))));
            ax.YTick = yt;
            ax.YTickLabel = cellstr(string(datetime(yt, 'ConvertFrom', 'datenum'), 'dd-MMM'));
            if chkT3Shared.Value && numel(lim) == 2 && lim(2) > lim(1)
                ax.CLim = lim;
                zlim(ax, lim);
            end
            xlabel(ax, 'Hour of day'); ylabel(ax, 'Date'); zlabel(ax, zlab);
            title(ax, P.ttl, 'Interpreter', 'none', 'FontSize', 9);
            grid(ax, 'on'); ax.Box = 'on';
            if ~chkT3Shared.Value || p == numel(panels), colorbar(ax); end
        end
        S.t3Link = [];
        if chkT3Link.Value && numel(axs) > 1
            S.t3Link = linkprop(axs, 'View');
        end
        tipAxes(axs);
    end

%% ================================================================ Circadian compare tab
    function refreshCCList()
        E = getEpochs();
        ks = selEpochs();
        if isempty(ks)
            taCCSel.Value = {'(none ticked)'};
            return;
        end
        items = cell(numel(ks), 1);
        for j = 1:numel(ks)
            items{j} = sprintf('%s  %s', E(ks(j)).label, S.files(E(ks(j)).fileIdx).name);
        end
        taCCSel.Value = items;
    end

    function ks = ccSelection()
        ks = selEpochs();
    end

    function [dt, v] = ccData(h, k, E)
        if strcmp(ddCCScope.Value, 'Epoch (non-overlapping)')
            [dt, v, dtU] = getTL(h);
            sel = assignEpoch(dtU, E) == k;
            dt = dt(sel); v = v(sel);
        else
            T = S.fileTL{E(k).fileIdx}.(h);
            [d, o] = sort(T.dt);
            v = T.v(o);
            if ~isempty(v)
                v(isoutlier(v, 'movmedian', 25, 'ThresholdFactor', spK.Value)) = NaN;
            end
            dt = localTime(d);
        end
    end

    function rows = plotCircCompare(axL, axR)
        rows = cell(0, 9);
        E = getEpochs();
        ks = ccSelection();
        normMode = ddCCNorm.Value;
        isZ = startsWith(normMode, 'z-score');
        cmap = tcolors(max(numel(ks), 1));
        ctr = ((0:143)' + 0.5) / 6;
        axs = {axL, axR}; hc = {'L', 'R'};
        for a = 1:2
            ax = axs{a}; h = hc{a};
            clearAxes(ax); legend(ax, 'off'); hold(ax, 'on');
            drew = false;
            for j = 1:numel(ks)
                k = ks(j);
                [dt, v] = ccData(h, k, E);
                ok = ~isnan(v) & v > 0;
                if sum(ok) < 10, continue; end
                dt = dt(ok); v = v(ok);
                if strcmp(normMode, 'Divide by file median')
                    v = v / median(v);
                elseif isZ
                    lv = log10(v);
                    v = (lv - mean(lv)) / std(lv);
                end
                hrs = hour(dt) + minute(dt) / 60;
                bin = floor((hour(dt) * 60 + minute(dt)) / 10) + 1;
                [m, q1, q3] = binStats(bin, v);
                plot(ax, ctr, m, '-', 'Color', cmap(j, :), 'LineWidth', 1.5, 'DisplayName', E(k).label);
                if chkCCIQR.Value
                    plot(ax, ctr, q1, ':', 'Color', cmap(j, :), 'HandleVisibility', 'off');
                    plot(ax, ctr, q3, ':', 'Color', cmap(j, :), 'HandleVisibility', 'off');
                end
                C = cosinor(hrs, v);
                relAmp = NaN;
                if ~isZ, relAmp = 100 * C.amp / C.mesor; end
                nDays = numel(unique(dateshift(dt, 'start', 'day')));
                rows(end+1, :) = {E(k).label, hemiName(h), nDays, numel(v), C.mesor, C.amp, ...
                    relAmp, hhmm(C.acro), C.R2}; %#ok<AGROW>
                drew = true;
            end
            hold(ax, 'off');
            xlim(ax, [0 24]);
            ax.XTick = 0:3:24;
            xlabel(ax, sprintf('Hour of day (%s)', tzName()), 'Interpreter', 'none');
            if isZ
                ylab = 'z (log_{10} power)';
            elseif strcmp(normMode, 'Divide by file median')
                ylab = 'Power / file median';
            else
                ylab = 'LFP power (a.u.)';
            end
            ylabel(ax, ylab);
            ax.YScale = ternary(chkLog.Value && ~isZ, 'log', 'linear');
            title(ax, sprintf('%s hemisphere', hemiName(h)));
            if drew
                legend(ax, 'Location', 'northeastoutside', 'Interpreter', 'none', 'Box', 'off');
            end
        end
        yl = [min(axL.YLim(1), axR.YLim(1)), max(axL.YLim(2), axR.YLim(2))];
        ylim(axL, yl); ylim(axR, yl);
        tipAxes([axL axR]);
    end

    function onCCPlot()
        if isempty(ccSelection())
            uialert(fig, 'Tick one or more sessions in the left panel (2+ to compare).', 'Circadian compare'); return;
        end
        rows = plotCircCompare(axCCL, axCCR);
        if isempty(rows)
            tblCC.Data = table();
        else
            tblCC.Data = cell2table(rows, 'VariableNames', {'Epoch', 'Hemisphere', 'Days', ...
                'Samples', 'MESOR', 'Amplitude', 'RelAmp_pct', 'Acrophase', 'R2'});
        end
    end

    function onCCPopout()
        if isempty(ccSelection())
            uialert(fig, 'Tick one or more sessions in the left panel first.', 'Circadian compare'); return;
        end
        f = figure('Name', 'Circadian compare', 'Color', 'w', 'Position', [80 80 1300 480]);
        t = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        axA = nexttile(t);
        axB = nexttile(t);
        plotCircCompare(axA, axB);
    end

%% ================================================================ Survey: frequency tab
    function refreshSurveyFreq()
        if isempty(S.montage)
            setDropdown(ddSFSess, {}, [], '(no LFPMontage data)');
            ddSFContact.Items = {'(none)'};
            for ax = [axSFL axSFR]
                clearAxes(ax); legend(ax, 'off'); title(ax, '');
            end
            tblSF.Data = table();
            return;
        end
        fisM = [S.montage.fileIdx];
        [items, data] = sessionItems(fisM(ismember(fisM, selFiles())));
        setDropdown(ddSFSess, items, data, '(no ticked session has LFPMontage)');
        contacts = unique({S.montage.contact});
        prev = ddSFContact.Value;
        ddSFContact.Items = contacts;
        if any(strcmp(contacts, prev)), ddSFContact.Value = prev; end
        refreshSurveyFreqPlot();
    end

    function refreshSurveyFreqPlot()
        if isempty(S.montage), return; end
        band = [efBetaLo.Value efBetaHi.Value];
        oneSession = startsWith(ddSFView.Value, 'All contacts');
        betaView = startsWith(ddSFView.Value, 'Beta per contact');
        E = getEpochs();
        rows = cell(0, 8);
        hc = {'L', 'R'}; axs = {axSFL, axSFR};
        for a = 1:2
            h = hc{a}; ax = axs{a};
            clearAxes(ax); legend(ax, 'off'); hold(ax, 'on');
            if betaView
                rows = [rows; sfBetaBars(ax, h, band, E)]; %#ok<AGROW>
                hold(ax, 'off');
                title(ax, sprintf('%s hemisphere: mean %g-%g Hz magnitude per contact', ...
                    hemiName(h), band), 'Interpreter', 'none');
                continue;
            end
            if oneSession
                sel = find([S.montage.fileIdx] == ddSFSess.Value & strcmp({S.montage.hemi}, h));
                cmap = tcolors(max(numel(sel), 1));
            else
                sel = find(strcmp({S.montage.contact}, ddSFContact.Value) & strcmp({S.montage.hemi}, h) ...
                    & ismember([S.montage.fileIdx], selFiles()));
                ks = zeros(size(sel));
                for q = 1:numel(sel)
                    ks(q) = find([E.fileIdx] == S.montage(sel(q)).fileIdx, 1);
                end
                [~, o] = sort(ks);
                sel = sel(o);
                cmap = tcolors(numel(sel));
            end
            fmax = 0;
            for j = 1:numel(sel)
                m = S.montage(sel(j));
                sl = sessLabel(m.fileIdx);
                if oneSession, lbl = m.contact; else, lbl = sl; end
                art = upper(m.artifact);
                if contains(art, 'PRESENT') && ~contains(art, 'NOT')
                    lbl = [lbl ' [artifact]']; %#ok<AGROW>
                end
                plot(ax, m.f, m.mag, '-', 'Color', cmap(j, :), 'LineWidth', 1.2, 'DisplayName', lbl);
                fmax = max(fmax, max(m.f));
                inB = m.f >= band(1) & m.f <= band(2);
                bm = NaN; bpk = NaN;
                if any(inB)
                    fb = m.f(inB); mb = m.mag(inB);
                    bm = mean(mb);
                    [~, jj] = max(mb);
                    bpk = fb(jj);
                end
                rows(end+1, :) = {sl, hemiName(h), m.contact, bm, bpk, m.peakF, m.peakMag, m.artifact}; %#ok<AGROW>
            end
            if ~isempty(sel)
                ax.YScale = ternary(chkSFLog.Value, 'log', 'linear');
                xlim(ax, [0 min(100, fmax)]);
                shadeBand(ax, band(1), band(2));
                legend(ax, 'Location', 'northeast', 'Interpreter', 'none', 'Box', 'off', 'FontSize', 8);
            end
            hold(ax, 'off');
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, 'LFP magnitude (device units)');
            if oneSession
                ttl = sprintf('%s hemisphere, %s', hemiName(h), sessLabel(ddSFSess.Value));
            else
                ttl = sprintf('%s hemisphere, contact %s', hemiName(h), ddSFContact.Value);
            end
            title(ax, ttl, 'Interpreter', 'none');
        end
        tipAxes([axSFL axSFR]);
        if isempty(rows)
            tblSF.Data = table();
            return;
        end
        T = cell2table(rows, 'VariableNames', {'Session', 'Hemisphere', 'Contact', 'BetaMean', ...
            'BetaPeakHz', 'DevicePeakHz', 'DevicePeakMag', 'Artifact'});
        tblSF.Data = sortrows(T, {'Session', 'Hemisphere', 'BetaMean'}, {'ascend', 'ascend', 'descend'});
    end

    function rows = sfBetaBars(ax, h, band, E)
        % Grouped bars: mean beta magnitude per contact pair x ticked session.
        rows = cell(0, 8);
        sel = find(strcmp({S.montage.hemi}, h) & ismember([S.montage.fileIdx], selFiles()));
        if isempty(sel), return; end
        contacts = unique({S.montage(sel).contact});
        sf = unique([S.montage(sel).fileIdx]);
        ks = arrayfun(@(fi) find([E.fileIdx] == fi, 1), sf);
        [~, o] = sort(ks);
        sf = sf(o);
        M = nan(numel(contacts), numel(sf));
        for j = sel
            m = S.montage(j);
            inB = m.f >= band(1) & m.f <= band(2);
            if ~any(inB), continue; end
            fb = m.f(inB); mb = m.mag(inB);
            [~, jj] = max(mb);
            M(strcmp(contacts, m.contact), sf == m.fileIdx) = mean(mb);
            rows(end+1, :) = {sessLabel(m.fileIdx), hemiName(h), m.contact, mean(mb), fb(jj), ...
                m.peakF, m.peakMag, m.artifact}; %#ok<AGROW>
        end
        b = bar(ax, 1:numel(contacts), M, 'grouped');
        cmap = tcolors(numel(sf));
        for q = 1:numel(b)
            b(q).FaceColor = cmap(q, :);
            b(q).DisplayName = sessLabel(sf(q));
        end
        ax.XTick = 1:numel(contacts);
        ax.XTickLabel = contacts;
        ax.TickLabelInterpreter = 'none';
        xtickangle(ax, 30);
        xlabel(ax, 'Contact pair'); ylabel(ax, 'Mean beta magnitude (device units)');
        legend(ax, 'Location', 'northeast', 'Interpreter', 'none', 'Box', 'off', 'FontSize', 8);
    end

%% ================================================================ Survey: time-domain tab
    function refreshSurveyTDList()
        S.tdLast = [];
        if isempty(S.surveyTD)
            setDropdown(ddTDSess, {}, [], '(no survey time-domain data)');
        else
            fisT = [S.surveyTD.fileIdx];
            [items, data] = sessionItems(fisT(ismember(fisT, selFiles())));
            setDropdown(ddTDSess, items, data, '(no ticked session has survey TD)');
        end
        refreshTDChannels();
    end

    function refreshTDChannels()
        fi = ddTDSess.Value;
        if isempty(S.surveyTD) || isequal(fi, 0)
            setDropdown(ddTDChan, {}, [], '(none)');
            return;
        end
        idx = find([S.surveyTD.fileIdx] == fi);
        keys = strcat({S.surveyTD(idx).hemi}, '|', {S.surveyTD(idx).channel});
        [~, o] = sort(keys);
        idx = idx(o);
        setDropdown(ddTDChan, {S.surveyTD(idx).channel}, idx, '(none)');
    end

    function onTDSessChange()
        refreshTDChannels();
        plotTDComp();
        onTDChannelChange();
    end

    function R = tdAnalyze(idxs)
        pooled = startsWith(ddTDThrMode.Value, 'Pooled');
        indiv  = startsWith(ddTDBand.Value, 'Individual');
        fixedBand = [efBetaLo.Value efBetaHi.Value];
        pct = efTDThr.Value;
        minMs = efTDMin.Value;
        fiAll = [S.surveyTD.fileIdx];
        hmAll = {S.surveyTD.hemi};
        allIdx = idxs(:)';
        if pooled
            for i = idxs(:)'
                allIdx = [allIdx, find(fiAll == fiAll(i) & strcmp(hmAll, hmAll{i}))]; %#ok<AGROW>
            end
            allIdx = unique(allIdx);
        end
        C = struct('x', {}, 'fs', {}, 'Pw', {}, 'fw', {}, 'band', {}, 'peakF', {}, ...
            'xf', {}, 'env', {}, 'valid', {});
        for j = 1:numel(allIdx)
            s = S.surveyTD(allIdx(j));
            x = prepSignal(s.x);
            [Pw, fw] = welchPSD(x, s.fs, 1);
            pk = peakIn(fw, Pw, fixedBand);
            if indiv, band = [pk - 3, pk + 3]; else, band = fixedBand; end
            [xf, env, valid] = burstEnvelope(x, s.fs, band);
            C(j).x = x; C(j).fs = s.fs; C(j).Pw = Pw; C(j).fw = fw; C(j).band = band;
            C(j).peakF = pk; C(j).xf = xf; C(j).env = env; C(j).valid = valid;
        end
        R = [];
        for i = idxs(:)'
            j = find(allIdx == i, 1);
            if pooled
                mem = find(fiAll(allIdx) == fiAll(i) & strcmp(hmAll(allIdx), hmAll{i}));
                pool = cell(numel(mem), 1);
                for q = 1:numel(mem)
                    pool{q} = C(mem(q)).env(C(mem(q)).valid);
                end
                thr = pctl(vertcat(pool{:}), pct);
            else
                thr = pctl(C(j).env(C(j).valid), pct);
            end
            B = detectBursts(C(j).env, C(j).valid, C(j).fs, thr, minMs);
            inB = C(j).fw >= C(j).band(1) & C(j).fw <= C(j).band(2);
            r = struct('idx', i, 'fileIdx', fiAll(i), 'session', sessLabel(fiAll(i)), ...
                'channel', S.surveyTD(i).channel, 'hemi', hmAll{i}, 'band', C(j).band, ...
                'peakF', C(j).peakF, 'betaPSD', mean(C(j).Pw(inB)), 'thr', thr, ...
                'n', numel(B.s), 'rate', B.rate, 'meanDur', mean(B.dur), 'medDur', median(B.dur), ...
                'pctLong', 100 * mean(B.dur > 400), 'pctTime', B.pctTime, 'meanAmp', mean(B.amp));
            r.B = B; r.x = C(j).x; r.xf = C(j).xf; r.env = C(j).env;
            r.fs = C(j).fs; r.Pw = C(j).Pw; r.fw = C(j).fw;
            R = [R; r]; %#ok<AGROW>
        end
    end

    function onTDAnalyzeSession()
        fi = ddTDSess.Value;
        if isempty(S.surveyTD) || isequal(fi, 0)
            uialert(fig, 'No survey time-domain data loaded.', 'Survey TD'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Beta bursts', 'Indeterminate', 'on');
        R = tdAnalyze(find([S.surveyTD.fileIdx] == fi));
        close(dlg);
        showTDResults(R);
    end

    function onTDAnalyzeAll()
        if isempty(S.surveyTD)
            uialert(fig, 'No survey time-domain data loaded.', 'Survey TD'); return;
        end
        idx = find(ismember([S.surveyTD.fileIdx], selFiles()));
        if isempty(idx)
            uialert(fig, 'None of the ticked sessions has survey time-domain data.', 'Survey TD'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Beta bursts (ticked sessions)', 'Indeterminate', 'on');
        R = tdAnalyze(idx);
        close(dlg);
        showTDResults(R);
    end

    function showTDResults(R)
        S.tdLast = R;
        S.tdTable = tdTable(R);
        tblTD.Data = S.tdTable;
        plotTDComp();
        onTDChannelChange();
    end

    function onTDChannelChange()
        if isempty(S.tdLast), return; end
        r = S.tdLast([S.tdLast.idx] == ddTDChan.Value);
        if isempty(r), return; end
        plotTDDetail(r(1));
    end

    function plotTDDetail(r)
        tt = (0:numel(r.x) - 1)' / r.fs;
        c = hcolSafe(r.hemi);
        ax = axTDTrace;
        clearAxes(ax); legend(ax, 'off'); hold(ax, 'on');
        plot(ax, tt, r.xf, 'Color', [0.78 0.78 0.78], 'DisplayName', 'Band-passed');
        plot(ax, tt, r.env, 'Color', c, 'LineWidth', 1.1, 'DisplayName', 'Envelope (200 ms)');
        plot(ax, tt([1 end]), [r.thr r.thr], 'r--', 'DisplayName', 'Threshold');
        yl = ax.YLim; ylim(ax, yl);
        if ~isempty(r.B.s)
            toBack(patch(ax, [tt(r.B.s) tt(r.B.e) tt(r.B.e) tt(r.B.s)]', ...
                repmat([yl(1); yl(1); yl(2); yl(2)], 1, numel(r.B.s)), [1 0.75 0.1], ...
                'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', 'Bursts'));
        end
        hold(ax, 'off');
        xlim(ax, tt([1 end]));
        xlabel(ax, 'Time (s)'); ylabel(ax, 'Amplitude (a.u.)');
        title(ax, sprintf('%s  %s  |  %.1f-%.1f Hz  |  %d bursts, %.1f /min', r.session, r.channel, ...
            r.band, r.n, r.rate), 'Interpreter', 'none');
        legend(ax, 'Box', 'off', 'Location', 'northeast');

        ax = axTDPSD;
        clearAxes(ax); legend(ax, 'off');
        k = r.fw >= 1 & r.fw <= min(100, r.fs / 2);
        plot(ax, r.fw(k), r.Pw(k), 'k-', 'LineWidth', 1.2, 'HandleVisibility', 'off');
        ax.YScale = 'log';
        hold(ax, 'on');
        shadeBand(ax, r.band(1), r.band(2));
        [~, j] = min(abs(r.fw - r.peakF));
        plot(ax, r.peakF, r.Pw(j), 'rv', 'MarkerFaceColor', 'r', ...
            'DisplayName', sprintf('Peak %.1f Hz', r.peakF));
        hold(ax, 'off');
        xlabel(ax, 'Frequency (Hz)'); ylabel(ax, 'PSD (a.u.^2/Hz)');
        title(ax, 'Welch PSD (1-s Hann)');
        legend(ax, 'Box', 'off');

        ax = axTDDur;
        clearAxes(ax);
        if ~isempty(r.B.dur)
            histogram(ax, r.B.dur, 'BinWidth', 50, 'FaceColor', c);
        end
        hold(ax, 'on');
        plot(ax, [400 400], ax.YLim, 'k--');
        hold(ax, 'off');
        xlabel(ax, 'Burst duration (ms)'); ylabel(ax, 'Count');
        title(ax, sprintf('Durations (median %.0f ms; dashed = 400 ms)', r.medDur));
        tipAxes([axTDTrace axTDPSD]);
    end

    function plotTDComp()
        clearAxes(axTDComp); legend(axTDComp, 'off');
        if isempty(S.tdLast), return; end
        R = S.tdLast;
        metric = ddTDMetric.Value;
        sf = unique([R.fileIdx]);
        if numel(sf) > 1
            % channels x sessions, grouped bars
            E = getEpochs();
            ks = arrayfun(@(fi) find([E.fileIdx] == fi, 1), sf);
            [~, o] = sort(ks);
            sf = sf(o);
            keys = unique(strcat({R.hemi}, '|', {R.channel}));
            M = nan(numel(keys), numel(sf));
            for q = 1:numel(R)
                M(strcmp(keys, [R(q).hemi '|' R(q).channel]), sf == R(q).fileIdx) = tdMetric(R(q), metric);
            end
            b = bar(axTDComp, 1:numel(keys), M, 'grouped');
            cmap = tcolors(numel(sf));
            for q = 1:numel(b)
                b(q).FaceColor = cmap(q, :);
                b(q).DisplayName = sessLabel(sf(q));
            end
            axTDComp.XTick = 1:numel(keys);
            axTDComp.XTickLabel = regexprep(keys, '^.*\|', '');
            axTDComp.TickLabelInterpreter = 'none';
            xtickangle(axTDComp, 40);
            ylabel(axTDComp, metric);
            legend(axTDComp, 'Location', 'northeast', 'Interpreter', 'none', 'Box', 'off', 'FontSize', 8);
            title(axTDComp, 'Per channel across ticked sessions');
            return;
        end
        keys = strcat({R.hemi}, '|', {R.channel});
        [~, o] = sort(keys);
        R = R(o);
        vals = arrayfun(@(r) tdMetric(r, metric), R);
        cols = zeros(numel(R), 3);
        for q = 1:numel(R), cols(q, :) = hcolSafe(R(q).hemi); end
        b = bar(axTDComp, 1:numel(R), vals, 'FaceColor', 'flat');
        b.CData = cols;
        axTDComp.XTick = 1:numel(R);
        axTDComp.XTickLabel = {R.channel};
        axTDComp.TickLabelInterpreter = 'none';
        xtickangle(axTDComp, 40);
        ylabel(axTDComp, metric);
        title(axTDComp, sprintf('%s per channel (blue = L, orange = R)', R(1).session), ...
            'Interpreter', 'none');
    end

    function onTDExport()
        if isempty(S.tdTable)
            uialert(fig, 'Run an analysis first.', 'Export'); return;
        end
        [f, p] = uiputfile('*.csv', 'Save burst table', 'survey_bursts.csv');
        figure(fig);
        if isequal(f, 0), return; end
        writetable(S.tdTable, fullfile(p, f));
    end

%% ================================================================ Periodic / aperiodic tab
    function lbl = fitItemLabel(i)
        switch ddFitSrc.Value
            case 'Survey (LFPMontage)'
                m = S.montage(i);
                lbl = sprintf('%s | %s | %s', sessLabel(m.fileIdx), hemiName(m.hemi), m.contact);
            case 'Survey TD (Welch)'
                s = S.surveyTD(i);
                lbl = sprintf('%s | %s', sessLabel(s.fileIdx), s.channel);
            otherwise
                s = S.streams(i);
                lbl = sprintf('%s | %s | %s', sessLabel(s.fileIdx), s.source, s.channel);
        end
    end

    function arr = fitSourceArray()
        switch ddFitSrc.Value
            case 'Survey (LFPMontage)', arr = S.montage;
            case 'Survey TD (Welch)',   arr = S.surveyTD;
            otherwise,                  arr = S.streams;
        end
    end

    function [labels, data] = fitItemList()
        arr = fitSourceArray();
        labels = {}; data = [];
        if isempty(arr), return; end
        data = find(ismember([arr.fileIdx], selFiles()));
        labels = arrayfun(@(i) fitItemLabel(i), data, 'UniformOutput', false);
    end

    function refreshFitItems()
        [labels, data] = fitItemList();
        setDropdown(ddFitItem, labels, data, '(none in ticked sessions)');
    end

    function D = getFitData(i)
        D = struct('f', [], 'P', [], 'x', [], 'fs', NaN, 'win', NaN, 'label', '', 'hemi', '');
        D.label = fitItemLabel(i);
        switch ddFitSrc.Value
            case 'Survey (LFPMontage)'
                m = S.montage(i);
                D.f = m.f; D.P = m.mag; D.hemi = m.hemi;
                if chkSquare.Value, D.P = D.P .^ 2; end
            otherwise
                if startsWith(ddFitSrc.Value, 'Survey'), s = S.surveyTD(i); else, s = S.streams(i); end
                D.x = prepSignal(s.x);
                D.fs = s.fs;
                D.hemi = s.hemi;
                D.win = ternary(numel(D.x) / s.fs >= 10, 2, 1);
                [D.P, D.f] = welchPSD(D.x, D.fs, D.win);
        end
    end

    function R = runFit(i)
        D = getFitData(i);
        band = [efBetaLo.Value efBetaHi.Value];
        frange = [efFitLo.Value efFitHi.Value];
        if frange(1) >= frange(2), error('Fit range: low must be below high.'); end
        if strcmp(ddFitMethod.Value, 'IRASA')
            if isempty(D.x)
                error('IRASA needs a time series: choose Survey TD or Streaming as the source.');
            end
            R = irasa(D.x, D.fs, D.win, frange, band);
        else
            opt.mode = ternary(contains(ddFitMethod.Value, 'knee'), 'knee', 'fixed');
            opt.pwl = [efPWLo.Value efPWHi.Value];
            opt.maxPeaks = efMaxPk.Value;
            opt.minHeight = efMinHt.Value;
            opt.peakThr = efPkThr.Value;
            R = fooofFit(D.f, D.P, frange, opt);
            R.betaCF = NaN; R.betaPW = NaN; R.betaBW = NaN;
            if ~isempty(R.peaks)
                inB = R.peaks(:, 1) >= band(1) & R.peaks(:, 1) <= band(2);
                if any(inB)
                    pb = R.peaks(inB, :);
                    [~, j] = max(pb(:, 2));
                    R.betaCF = pb(j, 1); R.betaPW = pb(j, 2); R.betaBW = pb(j, 3);
                end
            end
        end
        R.label = D.label;
        R.hemi = D.hemi;
        R.band = band;
        [R.bfm, R.uhdrs] = fitItemScore(i);
    end

    function onFit()
        i = ddFitItem.Value;
        if isequal(i, 0)
            uialert(fig, 'Nothing to fit for this source.', 'Fit'); return;
        end
        try
            R = runFit(i);
        catch ME
            uialert(fig, ME.message, 'Fit failed'); return;
        end
        plotFit(R);
        if isempty(R.peaks)
            tblFit.Data = table();
        else
            tblFit.Data = array2table(R.peaks, 'VariableNames', {'CF_Hz', 'PW_log10', 'BW_Hz'});
        end
    end

    function plotFit(R)
        clearAxes(axFit); legend(axFit, 'off');
        clearAxes(axFlat); legend(axFlat, 'off');
        if strcmp(R.method, 'IRASA')
            k = R.mask;
            plot(axFit, R.f(k), log10(R.Ptot(k)), 'k-', 'LineWidth', 1.3, 'DisplayName', 'Total (Welch)');
            hold(axFit, 'on');
            plot(axFit, R.f(k), log10(R.Pap(k)), 'b-', 'LineWidth', 1.3, 'DisplayName', 'Aperiodic (IRASA)');
            plot(axFit, R.f(k), R.offset - R.exponent * log10(R.f(k)), 'r--', 'DisplayName', 'Power-law fit');
            hold(axFit, 'off');
            plot(axFlat, R.f(k), log10(R.Ptot(k) ./ R.Pap(k)), 'k-', 'LineWidth', 1.3, ...
                'DisplayName', 'log_{10}(total / aperiodic)');
            hold(axFlat, 'on');
            if ~isnan(R.betaCF)
                plot(axFlat, R.betaCF, R.betaPW, 'rv', 'MarkerFaceColor', 'r', ...
                    'DisplayName', sprintf('Beta peak %.1f Hz', R.betaCF));
            end
            ttlFlat = 'Periodic component (IRASA)';
        else
            plot(axFit, R.f, R.y, 'k-', 'LineWidth', 1.3, 'DisplayName', 'Spectrum');
            hold(axFit, 'on');
            plot(axFit, R.f, R.model, 'r-', 'LineWidth', 1.3, 'DisplayName', 'Full model');
            plot(axFit, R.f, R.apFit, 'b--', 'LineWidth', 1.3, 'DisplayName', 'Aperiodic fit');
            hold(axFit, 'off');
            plot(axFlat, R.f, R.flat, 'k-', 'LineWidth', 1.3, 'DisplayName', 'Flattened');
            hold(axFlat, 'on');
            plot(axFlat, R.f, R.peakFit, 'g-', 'LineWidth', 1.3, 'DisplayName', 'Gaussian peaks');
            for q = 1:size(R.peaks, 1)
                plot(axFlat, R.peaks(q, 1), R.peaks(q, 2), 'rv', 'MarkerFaceColor', 'r', ...
                    'HandleVisibility', 'off');
                text(axFlat, R.peaks(q, 1), R.peaks(q, 2), sprintf('  %.1f Hz', R.peaks(q, 1)), ...
                    'FontSize', 9, 'VerticalAlignment', 'bottom');
            end
            ttlFlat = 'Flattened spectrum (data - aperiodic) and peaks';
        end
        plot(axFlat, axFlat.XLim, [0 0], ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
        shadeBand(axFlat, R.band(1), R.band(2));
        hold(axFlat, 'off');
        xlabel(axFit, 'Frequency (Hz)'); ylabel(axFit, 'log_{10} power');
        title(axFit, sprintf('%s  [%s]', R.label, R.method), 'Interpreter', 'none');
        legend(axFit, 'Box', 'off');
        xlabel(axFlat, 'Frequency (Hz)'); ylabel(axFlat, 'log_{10} power above aperiodic');
        title(axFlat, ttlFlat);
        legend(axFlat, 'Box', 'off');
        taFit.Value = fitSummary(R);
        tipAxes([axFit axFlat]);
    end

    function onFitAll()
        [labels, data] = fitItemList();
        if isempty(data)
            uialert(fig, 'No items for this source.', 'Fit all'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Fitting', 'Value', 0);
        rows = cell(0, 14);
        fails = 0;
        for q = 1:numel(data)
            dlg.Value = q / numel(data);
            dlg.Message = labels{q};
            try
                R = runFit(data(q));
            catch
                fails = fails + 1;
                continue;
            end
            rows(end+1, :) = {R.label, hemiName(R.hemi), R.bfm, R.uhdrs, R.method, R.offset, R.exponent, R.knee, ...
                R.R2, R.err, size(R.peaks, 1), R.betaCF, R.betaPW, R.betaBW}; %#ok<AGROW>
        end
        close(dlg);
        if isempty(rows)
            uialert(fig, 'All fits failed (check source, method and fit range).', 'Fit all'); return;
        end
        S.fitTable = cell2table(rows, 'VariableNames', {'Item', 'Hemisphere', 'BFMDRS', 'UHDRS', 'Method', 'Offset', ...
            'Exponent', 'Knee', 'R2', 'Error', 'NPeaks', 'BetaCF', 'BetaPW', 'BetaBW'});
        tblFit.Data = S.fitTable;
        if fails > 0
            uialert(fig, sprintf('%d item(s) failed and were skipped.', fails), 'Fit all', 'Icon', 'warning');
        end
    end

    function onFitCompare()
        % Same contact pair / channel fitted in every ticked session and overlaid.
        i = ddFitItem.Value;
        if isequal(i, 0)
            uialert(fig, 'Pick an item first.', 'Compare'); return;
        end
        arr = fitSourceArray();
        ref = arr(i);
        if isfield(ref, 'contact')
            match = strcmp({arr.contact}, ref.contact) & strcmp({arr.hemi}, ref.hemi);
        else
            match = strcmp({arr.channel}, ref.channel) & strcmp({arr.source}, ref.source);
        end
        cand = find(match & ismember([arr.fileIdx], selFiles()));
        [ufi, first] = unique([arr(cand).fileIdx], 'stable');
        cand = cand(first);
        E = getEpochs();
        ks = arrayfun(@(fi) find([E.fileIdx] == fi, 1), ufi);
        [~, o] = sort(ks);
        cand = cand(o);
        if numel(cand) < 2
            uialert(fig, 'This contact/channel is present in fewer than 2 ticked sessions.', 'Compare'); return;
        end
        itemName = regexprep(fitItemLabel(i), '^[^|]*\|\s*', '');
        cmap = tcolors(numel(cand));
        clearAxes(axFit); legend(axFit, 'off'); clearAxes(axFlat); legend(axFlat, 'off');
        hold(axFit, 'on'); hold(axFlat, 'on');
        rows = cell(0, 11);
        txt = {sprintf('%s across %d ticked sessions', itemName, numel(cand))};
        for q = 1:numel(cand)
            try
                R = runFit(cand(q));
            catch ME
                txt{end+1, 1} = sprintf('%s: %s', fitItemLabel(cand(q)), ME.message); %#ok<AGROW>
                continue;
            end
            sl = sessLabel(arr(cand(q)).fileIdx);
            c = cmap(q, :);
            if strcmp(R.method, 'IRASA')
                k = R.mask;
                plot(axFit, R.f(k), log10(R.Ptot(k)), '-', 'Color', c + (1 - c) * 0.55, 'HandleVisibility', 'off');
                plot(axFit, R.f(k), log10(R.Pap(k)), '-', 'Color', c, 'LineWidth', 1.6, 'DisplayName', sl);
                plot(axFlat, R.f(k), log10(R.Ptot(k) ./ R.Pap(k)), '-', 'Color', c, 'LineWidth', 1.4, 'DisplayName', sl);
            else
                plot(axFit, R.f, R.y, '-', 'Color', c + (1 - c) * 0.55, 'HandleVisibility', 'off');
                plot(axFit, R.f, R.apFit, '-', 'Color', c, 'LineWidth', 1.6, 'DisplayName', sl);
                plot(axFlat, R.f, R.flat, '-', 'Color', c, 'LineWidth', 1.4, 'DisplayName', sl);
            end
            rows(end+1, :) = {sl, R.bfm, R.uhdrs, R.offset, R.exponent, R.knee, R.R2, size(R.peaks, 1), ...
                R.betaCF, R.betaPW, R.betaBW}; %#ok<AGROW>
        end
        if ~isempty(rows)
            plot(axFlat, axFlat.XLim, [0 0], ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
            shadeBand(axFlat, efBetaLo.Value, efBetaHi.Value);
        end
        hold(axFit, 'off'); hold(axFlat, 'off');
        xlabel(axFit, 'Frequency (Hz)'); ylabel(axFit, 'log_{10} power');
        title(axFit, sprintf('%s: spectra (light) and aperiodic fits [%s]', itemName, ddFitMethod.Value), ...
            'Interpreter', 'none');
        legend(axFit, 'Box', 'off', 'Interpreter', 'none');
        xlabel(axFlat, 'Frequency (Hz)'); ylabel(axFlat, 'log_{10} power above aperiodic');
        title(axFlat, 'Periodic component per session');
        legend(axFlat, 'Box', 'off', 'Interpreter', 'none');
        if isempty(rows)
            taFit.Value = txt; return;
        end
        S.fitTable = cell2table(rows, 'VariableNames', {'Session', 'BFMDRS', 'UHDRS', 'Offset', 'Exponent', 'Knee', ...
            'R2', 'NPeaks', 'BetaCF', 'BetaPW', 'BetaBW'});
        tblFit.Data = S.fitTable;
        fmtSeq = @(v) strjoin(arrayfun(@(e) sprintf('%.3g', e), v, 'UniformOutput', false), ' -> ');
        txt{end+1, 1} = ['BFMDRS   : ' fmtSeq(cell2mat(rows(:, 2)))];
        txt{end+1, 1} = ['UHDRS    : ' fmtSeq(cell2mat(rows(:, 3)))];
        txt{end+1, 1} = ['Exponent : ' fmtSeq(cell2mat(rows(:, 5)))];
        txt{end+1, 1} = ['Offset   : ' fmtSeq(cell2mat(rows(:, 4)))];
        txt{end+1, 1} = ['Beta CF  : ' fmtSeq(cell2mat(rows(:, 9)))];
        txt{end+1, 1} = ['Beta PW  : ' fmtSeq(cell2mat(rows(:, 10)))];
        taFit.Value = txt;
        tipAxes([axFit axFlat]);
    end

    function onFitExport()
        if isempty(S.fitTable)
            uialert(fig, 'Run "Fit all items" first.', 'Export'); return;
        end
        [f, p] = uiputfile('*.csv', 'Save fit table', 'spectral_parameters.csv');
        figure(fig);
        if isequal(f, 0), return; end
        writetable(S.fitTable, fullfile(p, f));
    end

%% ================================================================ Overview tab
    function refreshOverview()
        E = getEpochs();
        S.ovRows = [E.fileIdx];
        clearAxes(axOvAmp); legend(axOvAmp, 'off');
        clearAxes(axOvFreq); legend(axOvFreq, 'off');
        if isempty(E)
            tblOv.Data = table();
            return;
        end
        n = numel(E);
        C = cell(n, 24);
        for k = 1:n
            fi = E(k).fileIdx;
            F = S.files(fi);
            st = F.stim;
            [bv, uv, bs, us] = sessScore(fi);
            C(k, :) = {S.use(fi), E(k).label, F.name, ...
                char(string(localTime(F.sessionDate), 'yyyy-MM-dd HH:mm')), [num2s(bv) bs], [num2s(uv) us], st.group, ...
                ampStr(st.L), num2s(st.L.rate), num2s(st.L.pw), st.L.contacts, ...
                ampStr(st.R), num2s(st.R.rate), num2s(st.R.pw), st.R.contacts, ...
                tlAmpStr('L', k, E), tlAmpStr('R', k, E), ...
                sprintf('%s @ %s Hz', F.sens.chL, num2s(F.sens.foiL)), ...
                sprintf('%s @ %s Hz', F.sens.chR, num2s(F.sens.foiR)), st.aDBS, ...
                sprintf('%d spec / %d TD', F.nMon, F.nTD), sprintf('%d', F.nStr), ...
                sprintf('%d / %d', F.nL, F.nR), sprintf('%d', F.nEv)};
        end
        tblOv.Data = cell2table(C, 'VariableNames', {'Use', 'Session', 'File', 'Date', 'BFMDRS', 'UHDRS', 'Group', ...
            'L_mA', 'L_Hz', 'L_us', 'L_contacts', 'R_mA', 'R_Hz', 'R_us', 'R_contacts', ...
            'Timeline_mA_L', 'Timeline_mA_R', 'Sense_FOI_L', 'Sense_FOI_R', 'aDBS', ...
            'Survey', 'Streaming', 'Timeline_LR', 'Events'});
        plotOverview(E);
    end

    function s = tlAmpStr(h, k, E)
        % Timeline stimulation amplitude in epoch k: median [min-max].
        s = '-';
        T = S.tl.(h);
        if isempty(T.amp), return; end
        a = T.amp(assignEpoch(T.dt, E) == k);
        a = a(~isnan(a));
        if isempty(a), return; end
        s = sprintf('%.2g [%.2g-%.2g]', median(a), min(a), max(a));
    end

    function plotOverview(E)
        x = datenum(localTime(vertcat(S.files([E.fileIdx]).sessionDate)));
        if all(isnan(x)), return; end
        hold(axOvAmp, 'on'); hold(axOvFreq, 'on');
        mk = {'o', 's'}; hc = {'L', 'R'};
        top = 0;
        for a = 1:2
            h = hc{a}; c = hcol(h);
            n = numel(E);
            amp = nan(n, 1); rate = amp; foi = amp; lo = amp; hi = amp; med = amp;
            T = S.tl.(h);
            epT = assignEpoch(T.dt, E);
            for k = 1:n
                F = S.files(E(k).fileIdx);
                if ~isempty(F.stim.(h).amps), amp(k) = F.stim.(h).amps(1); end
                rate(k) = F.stim.(h).rate;
                foi(k) = F.sens.(['foi' h]);
                aa = T.amp(epT == k);
                aa = aa(~isnan(aa));
                if ~isempty(aa), lo(k) = min(aa); hi(k) = max(aa); med(k) = median(aa); end
            end
            off = (a - 1.5) * 0.25;
            X = [x' + off; x' + off; nan(1, n)];
            Y = [lo'; hi'; nan(1, n)];
            plot(axOvAmp, X(:), Y(:), '-', 'Color', c + (1 - c) * 0.5, 'LineWidth', 5, ...
                'DisplayName', [hemiName(h) ' Timeline range']);
            plot(axOvAmp, x + off, med, 'd', 'Color', c, 'DisplayName', [hemiName(h) ' Timeline median']);
            plot(axOvAmp, x, amp, ['-' mk{a}], 'Color', c, 'MarkerFaceColor', c, ...
                'DisplayName', [hemiName(h) ' programmed (session end)']);
            plot(axOvFreq, x, rate, ['-' mk{a}], 'Color', c, 'MarkerFaceColor', c, ...
                'DisplayName', [hemiName(h) ' stim rate']);
            plot(axOvFreq, x, foi, [':' mk{a}], 'Color', c, 'DisplayName', [hemiName(h) ' sensing FOI']);
            top = max([top; amp; hi], [], 'omitnan');
        end
        hold(axOvAmp, 'off'); hold(axOvFreq, 'off');
        xl = [min(x) - 2, max(x) + 2];
        for ax = [axOvAmp axOvFreq]
            xlim(ax, xl);
            setDateTicks(ax);
            legend(ax, 'Location', 'northeastoutside', 'Box', 'off', 'FontSize', 8);
        end
        if top > 0, ylim(axOvAmp, [0 top * 1.15]); end
        ylabel(axOvAmp, 'Amplitude (mA)');
        title(axOvAmp, 'Stimulation amplitude per session (all sessions)');
        axOvFreq.YScale = 'log';
        ylabel(axOvFreq, 'Frequency (Hz)');
        title(axOvFreq, 'Stimulation rate and sensing FOI per session');
        tipAxes([axOvAmp axOvFreq]);
    end

    function onOvSelect(evt)
        if isempty(evt.Indices), return; end
        r = evt.Indices(1, 1);
        if r > numel(S.ovRows), return; end
        F = S.files(S.ovRows(r));
        st = F.stim;
        hs = {'L', st.L; 'R', st.R};
        txt = {F.name; sprintf('Active group at session end: %s', st.group); ''};
        for q = 1:2
            x = hs{q, 2};
            txt{end+1, 1} = sprintf('%s: %s mA, %s Hz, %s us, contacts %s (%d program(s))', ...
                hemiName(hs{q, 1}), ampStr(x), num2s(x.rate), num2s(x.pw), x.contacts, x.nProg); %#ok<AGROW>
        end
        txt{end+1, 1} = sprintf('Sensing: L %s @ %s Hz | R %s @ %s Hz', F.sens.chL, num2s(F.sens.foiL), ...
            F.sens.chR, num2s(F.sens.foiR));
        txt{end+1, 1} = '';
        txt{end+1, 1} = sprintf('aDBS: %s', st.aDBS);
        txt{end+1, 1} = 'Fields matching adaptive/threshold/limit/capture/ramp:';
        if isempty(st.adaptive)
            txt{end+1, 1} = '  (none found)';
        else
            txt = [txt; strcat({'  '}, st.adaptive(:))];
        end
        taOv.Value = txt;
    end

%% ================================================================ Streaming compare tab
    function r = scPickRecording(fi)
        % [iL iR]: L and R channel indices of one recording in session fi.
        r = [NaN NaN];
        if isempty(S.streams), return; end
        idx = find([S.streams.fileIdx] == fi & strcmp({S.streams.source}, ddSCSrc.Value));
        if isempty(idx), return; end
        key = string(vertcat(S.streams(idx).t0));
        [uk, ~, gi] = unique(key, 'stable');
        dur = zeros(numel(uk), 1); tn = dur;
        for g = 1:numel(uk)
            mem = idx(gi == g);
            dur(g) = max(arrayfun(@(i) numel(S.streams(i).x) / S.streams(i).fs, mem));
            tn(g) = datenum(S.streams(mem(1)).t0);
        end
        switch ddSCPick.Value
            case 'Longest', [~, gsel] = max(dur);
            case 'First',   [~, gsel] = min(tn);
            otherwise,      [~, gsel] = max(tn);
        end
        mem = idx(gi == gsel);
        hm = {S.streams(mem).hemi};
        iL = mem(strcmp(hm, 'L'));
        iR = mem(strcmp(hm, 'R'));
        if ~isempty(iL), r(1) = iL(1); end
        if ~isempty(iR), r(2) = iR(1); end
    end

    function onSCCompare()
        fis = selFilesChrono();
        if isempty(S.streams) || isempty(fis)
            uialert(fig, 'Load files and tick sessions with streaming recordings.', 'Streaming compare'); return;
        end
        band = [efBetaLo.Value efBetaHi.Value];
        win = efWin.Value;
        cols = struct('fi', {}, 'label', {}, 'i', {}, 'rec', {});
        for q = 1:numel(fis)
            rr = scPickRecording(fis(q));
            if all(isnan(rr)), continue; end
            cols(end+1).fi = fis(q); %#ok<AGROW>
            cols(end).label = sessLabel(fis(q));
            cols(end).i = rr;
            i0 = rr(~isnan(rr));
            [b0, u0, src0] = streamScore(i0(1));
            cols(end).rec = '';
            if startsWith(src0, 'recording'), cols(end).rec = [' | rec ' scoreText(b0, u0, true)]; end
        end
        if isempty(cols)
            uialert(fig, sprintf('None of the ticked sessions has %s recordings.', ddSCSrc.Value), ...
                'Streaming compare'); return;
        end
        dlg = uiprogressdlg(fig, 'Title', 'Comparing sessions', 'Indeterminate', 'on');
        n = numel(cols);
        hc = {'L', 'R'};
        A = cell(n, 2);
        for q = 1:n
            for a = 1:2
                i = cols(q).i(a);
                if isnan(i), continue; end
                st = S.streams(i);
                x = prepSignal(st.x);
                fs = st.fs;
                if numel(x) < 5 * fs, continue; end
                [P, f, t] = stftPower(x, fs, win, 0.9);
                kf = f <= min(100, fs / 2);
                [Pw, fw] = welchPSD(x, fs, max(win, 1));
                [~, env, valid] = burstEnvelope(x, fs, band);
                A{q, a} = struct('SdB', 10 * log10(P(kf, :) + eps), 'f', f(kf), 't', t, 'Pw', Pw, ...
                    'fw', fw, 'env', env, 'valid', valid, 'fs', fs, 'dur', numel(x) / fs, 'idx', i);
            end
        end
        % shared colour limits and burst thresholds
        allS = [];
        thr = nan(n, 2);
        for a = 1:2
            pool = {};
            for q = 1:n
                if isempty(A{q, a}), continue; end
                allS = [allS; A{q, a}.SdB(:)]; %#ok<AGROW>
                pool{end+1} = A{q, a}.env(A{q, a}.valid); %#ok<AGROW>
                thr(q, a) = pctl(pool{end}, efThr.Value);
            end
            if chkSCPool.Value && ~isempty(pool)
                thr(:, a) = pctl(vertcat(pool{:}), efThr.Value);
            end
        end
        clShared = pctl(allS, [2 99.5]);
        % spectrogram grid: rows = hemisphere, columns = sessions
        delete(gSC.Children);
        gSC.RowHeight = {'1x', '1x', 85};
        stimTop = 0.5;
        for q = 1:n
            for a = 1:2
                if ~isnan(cols(q).i(a))
                    so = S.streams(cols(q).i(a));
                    stimTop = max([stimTop; so.stimL(:); so.stimR(:)], [], 'omitnan');
                end
            end
        end
        stimTop = stimTop * 1.2;
        gSC.ColumnWidth = repmat({'1x'}, 1, n);
        for q = 1:n
            for a = 1:2
                ax = uiaxes(gSC);
                ax.Layout.Row = a;
                ax.Layout.Column = q;
                R = A{q, a};
                if isempty(R)
                    title(ax, sprintf('%s | %s: no recording', cols(q).label, hemiName(hc{a})), ...
                        'Interpreter', 'none', 'FontSize', 9);
                    continue;
                end
                imagesc(ax, R.t, R.f, R.SdB);
                ax.YDir = 'normal';
                colormap(ax, turbo);
                axis(ax, 'tight');
                if chkSCClim.Value
                    cl = clShared;
                else
                    cl = pctl(R.SdB(:), [2 99.5]);
                end
                if cl(2) > cl(1), ax.CLim = cl; end
                hold(ax, 'on');
                plot(ax, R.t([1 end]), band([1 1]), 'w--', R.t([1 end]), band([2 2]), 'w--');
                hold(ax, 'off');
                title(ax, sprintf('%s%s | %s %s', cols(q).label, cols(q).rec, hemiName(hc{a}), ...
                    S.streams(R.idx).channel), 'Interpreter', 'none', 'FontSize', 9);
                if q == 1, ylabel(ax, 'Frequency (Hz)'); end
                if a == 2, xlabel(ax, 'Time (s)'); end
                if q == n || ~chkSCClim.Value, colorbar(ax); end
            end
            % stimulation amplitude for this session's recording
            ax = uiaxes(gSC);
            ax.Layout.Row = 3;
            ax.Layout.Column = q;
            i0 = cols(q).i(~isnan(cols(q).i));
            so = S.streams(i0(1));
            if isempty(so.stimT) || all(isnan(so.stimT))
                title(ax, 'Stim: not available', 'FontSize', 8, 'FontWeight', 'normal');
            else
                hold(ax, 'on');
                stairs(ax, so.stimT, so.stimL, '-', 'Color', hcol('L'), 'LineWidth', 1.3, 'DisplayName', 'L');
                stairs(ax, so.stimT, so.stimR, '-', 'Color', hcol('R'), 'LineWidth', 1.3, 'DisplayName', 'R');
                hold(ax, 'off');
                ylim(ax, [0 stimTop]);
                xlim(ax, [0 numel(so.x) / so.fs]);
                title(ax, 'Stim (mA): blue = L, orange = R', 'FontSize', 8, 'FontWeight', 'normal');
                if q == 1, ylabel(ax, 'mA'); end
                tipAxes(ax);
            end
        end
        % PSD overlays and metrics
        cmap = tcolors(n);
        rows = cell(0, 15);
        opt = struct('mode', 'fixed', 'pwl', [1 12], 'maxPeaks', 6, 'minHeight', 0.1, 'peakThr', 2);
        axs = {axSCL, axSCR};
        pctNorm = contains(ddSCNorm.Value, '%');
        for a = 1:2
            ax = axs{a};
            clearAxes(ax); legend(ax, 'off'); hold(ax, 'on');
            drew = false;
            for q = 1:n
                R = A{q, a};
                if isempty(R), continue; end
                k = R.fw >= 1 & R.fw <= min(100, R.fs / 2);
                tot = sum(R.Pw(k));
                Pp = R.Pw;
                if pctNorm, Pp = 100 * Pp / tot; end
                plot(ax, R.fw(k), Pp(k), '-', 'Color', cmap(q, :), 'LineWidth', 1.3, ...
                    'DisplayName', cols(q).label);
                drew = true;
                inB = R.fw >= band(1) & R.fw <= band(2);
                pk = peakIn(R.fw, R.Pw, band);
                B = detectBursts(R.env, R.valid, R.fs, thr(q, a), efMinDur.Value);
                try
                    Rf = fooofFit(R.fw, R.Pw, [3 40], opt);
                    expo = Rf.exponent;
                catch
                    expo = NaN;
                end
                [bq, uq] = streamScore(R.idx);
                rows(end+1, :) = {cols(q).label, hemiName(hc{a}), S.streams(R.idx).channel, bq, uq, ...
                    stimMedian(R.idx, hc{a}), R.dur, pk, ...
                    100 * sum(R.Pw(inB)) / tot, numel(B.s), B.rate, mean(B.dur), ...
                    100 * mean(B.dur > 400), B.pctTime, expo}; %#ok<AGROW>
            end
            if drew
                ax.YScale = 'log';
                shadeBand(ax, band(1), band(2));
                legend(ax, 'Box', 'off', 'Interpreter', 'none', 'FontSize', 8);
            end
            hold(ax, 'off');
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, ternary(pctNorm, '% of 1-100 Hz power', 'PSD (a.u.^2/Hz)'));
            title(ax, sprintf('%s: Welch PSD by session', hemiName(hc{a})));
        end
        tipAxes([axSCL axSCR]);
        tipAxes(findall(gSC, 'Type', 'axes'), 'Power (dB)');
        close(dlg);
        if isempty(rows)
            tblSC.Data = table();
        else
            tblSC.Data = cell2table(rows, 'VariableNames', {'Session', 'Hemi', 'Channel', 'BFMDRS', ...
                'UHDRS', 'Stim_mA', 'Dur_s', ...
                'PeakHz', 'BetaRelPct', 'NBursts', 'RatePerMin', 'MeanDurMs', 'PctLong', 'PctTime', ...
                'AperiodicExp'});
        end
    end

%% ================================================================ severity scores
    function [b, u, bs, us] = sessScore(fi)
        % Session score: manual entry if present, else the file-name value.
        % bs / us are '*' when the manual value is used.
        F = S.files(fi);
        b = F.bfm; u = F.uhdrs; bs = ''; us = '';
        if ~isnan(F.bfmMan), b = F.bfmMan; bs = '*'; end
        if ~isnan(F.uhdrsMan), u = F.uhdrsMan; us = '*'; end
    end

    function [b, u, src] = streamScore(i)
        % Recording-level manual score, else the session's score.
        st_ = S.streams(i);
        [b, u, bs, us] = sessScore(st_.fileIdx);
        if isnan(b) && isnan(u)
            src = 'none';
        elseif ~isempty(bs) || ~isempty(us)
            src = 'session, manual';
        else
            src = 'session file name';
        end
        if ~isnan(st_.bfmMan) || ~isnan(st_.uhdrsMan)
            if ~isnan(st_.bfmMan), b = st_.bfmMan; end
            if ~isnan(st_.uhdrsMan), u = st_.uhdrsMan; end
            src = 'recording, manual';
        end
    end

    function [b, u] = fitItemScore(i)
        if startsWith(ddFitSrc.Value, 'Streaming')
            [b, u] = streamScore(i);
        else
            arr = fitSourceArray();
            [b, u] = sessScore(arr(i).fileIdx);
        end
    end

    function m = stimMedian(i, h)
        m = NaN;
        st_ = S.streams(i);
        if strcmp(h, 'L'), v = st_.stimL; else, v = st_.stimR; end
        if ~isempty(v) && any(~isnan(v)), m = median(v, 'omitnan'); end
    end

    function openScoreEditor()
        E = getEpochs();
        if isempty(E)
            uialert(fig, 'Load files first.', 'Scores'); return;
        end
        n = numel(E);
        C = cell(n, 6);
        for k = 1:n
            F = S.files(E(k).fileIdx);
            C(k, :) = {sprintf('E%d', k), F.name, F.bfm, F.uhdrs, F.bfmMan, F.uhdrsMan};
        end
        pos = fig.Position;
        dlgF = uifigure('Name', 'Session severity scores', 'WindowStyle', 'modal', ...
            'Position', [pos(1) + 80, pos(2) + 80, 760, 420]);
        gD = uigridlayout(dlgF, [3 1]);
        gD.RowHeight = {44, '1x', 32};
        uilabel(gD, 'WordWrap', 'on', 'Text', ['File_ columns: scores parsed from file names. ' ...
            'Type a Manual_ value to fill a missing score or override it; enter NaN to remove it. ' ...
            'Manual values are marked * in labels.']);
        tbD = uitable(gD, 'RowName', {}, 'Data', cell2table(C, 'VariableNames', ...
            {'Epoch', 'File', 'File_BFMDRS', 'File_UHDRS', 'Manual_BFMDRS', 'Manual_UHDRS'}), ...
            'ColumnEditable', [false false false false true true]);
        gBtn = uigridlayout(gD, [1 3]);
        gBtn.Padding = [0 0 0 0];
        gBtn.ColumnWidth = {'1x', 100, 100};
        uilabel(gBtn, 'Text', '');
        uibutton(gBtn, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) delete(dlgF));
        uibutton(gBtn, 'Text', 'Apply', 'ButtonPushedFcn', @(~,~) applyScores(tbD, E, dlgF));
    end

    function applyScores(tbD, E, dlgF)
        T = tbD.Data;
        for k = 1:numel(E)
            fi = E(k).fileIdx;
            S.files(fi).bfmMan = double(T.Manual_BFMDRS(k));
            S.files(fi).uhdrsMan = double(T.Manual_UHDRS(k));
        end
        delete(dlgF);
        refreshAll();
    end

%% ================================================================ streaming: stim, scores, segments
    function i = curStream()
        i = ddStream.Value;
        if isempty(S.streams) || ~isnumeric(i) || isequal(i, 0) || i > numel(S.streams)
            i = 0;
        end
    end

    function onStreamSelect()
        i = curStream();
        if i == 0
            efStB.Value = ''; efStU.Value = '';
            lblStSrc.Text = '';
            tblStSeg.Data = table();
            clearAxes(axStimSt); legend(axStimSt, 'off'); title(axStimSt, '');
            return;
        end
        [b, u, src] = streamScore(i);
        efStB.Value = num2sBlank(b);
        efStU.Value = num2sBlank(u);
        lblStSrc.Text = ['Score source: ' src];
        plotStreamStim();
        refreshSegTable();
    end

    function onStreamScoreSave()
        i = curStream();
        if i == 0, return; end
        b = str2double(efStB.Value);
        u = str2double(efStU.Value);
        [sb, su] = sessScore(S.streams(i).fileIdx);
        % keep a recording-level value only where it differs from the session's
        if isequaln(b, sb), S.streams(i).bfmMan = NaN; else, S.streams(i).bfmMan = b; end
        if isequaln(u, su), S.streams(i).uhdrsMan = NaN; else, S.streams(i).uhdrsMan = u; end
        onStreamSelect();
        if ~isempty(S.stLast) && S.stLast.idx == i
            [b2, u2] = streamScore(i);
            st_ = S.streams(i);
            title(axSpec, sprintf('Spectrogram (dB)  %s  %s  |  %s', st_.source, st_.channel, ...
                scoreText(b2, u2)), 'Interpreter', 'none');
        end
    end

    function plotStreamStim()
        ax = axStimSt;
        clearAxes(ax); legend(ax, 'off');
        i = curStream();
        if i == 0, return; end
        st_ = S.streams(i);
        dur = numel(st_.x) / st_.fs;
        if isempty(st_.stimT) || all(isnan(st_.stimT))
            xlim(ax, [0 dur]);
            title(ax, 'No stimulation data for this recording (BrainSenseLfp not found)', ...
                'FontWeight', 'normal', 'FontSize', 9);
        else
            hold(ax, 'on');
            stairs(ax, st_.stimT, st_.stimL, '-', 'Color', hcol('L'), ...
                'LineWidth', ternary(strcmp(st_.hemi, 'L'), 2, 1), 'DisplayName', 'Left');
            stairs(ax, st_.stimT, st_.stimR, '-', 'Color', hcol('R'), ...
                'LineWidth', ternary(strcmp(st_.hemi, 'R'), 2, 1), 'DisplayName', 'Right');
            top = max([st_.stimL(:); st_.stimR(:); 0.5], [], 'omitnan') * 1.3;
            ylim(ax, [0 top]);
            sg = st_.segs;
            for q = 1:size(sg, 1)
                toBack(patch(ax, [sg(q, 1) sg(q, 2) sg(q, 2) sg(q, 1)], [0 0 top top], [0.5 0.5 0.5], ...
                    'FaceAlpha', 0.12, 'EdgeColor', [0.45 0.45 0.45], 'HandleVisibility', 'off'));
                text(ax, mean(sg(q, 1:2)), top, sprintf('#%d %s', q, scoreText(sg(q, 3), sg(q, 4), true)), ...
                    'VerticalAlignment', 'top', 'HorizontalAlignment', 'center', 'FontSize', 8);
            end
            hold(ax, 'off');
            xlim(ax, [0 dur]);
            legend(ax, 'Location', 'northeastoutside', 'Box', 'off', 'FontSize', 8);
            title(ax, 'Stimulation amplitude (thicker = recorded hemisphere); shaded = segments', ...
                'FontWeight', 'normal', 'FontSize', 9);
        end
        xlabel(ax, 'Time (s)'); ylabel(ax, 'Stim (mA)');
        tipAxes(ax);
    end

    function refreshSegTable()
        i = curStream();
        if i == 0 || isempty(S.streams(i).segs)
            tblStSeg.Data = table();
            return;
        end
        st_ = S.streams(i);
        sg = st_.segs;
        n = size(sg, 1);
        mL = nan(n, 1); mR = mL; bp = mL;
        haveBeta = ~isempty(S.stLast) && S.stLast.idx == i;
        for q = 1:n
            if ~isempty(st_.stimT)
                in = st_.stimT >= sg(q, 1) & st_.stimT <= sg(q, 2);
                if any(in)
                    mL(q) = median(st_.stimL(in), 'omitnan');
                    mR(q) = median(st_.stimR(in), 'omitnan');
                end
            end
            if haveBeta
                inT = S.stLast.t >= sg(q, 1) & S.stLast.t <= sg(q, 2);
                if any(inT), bp(q) = 10 * log10(mean(S.stLast.beta(inT))); end
            end
        end
        tblStSeg.Data = table((1:n)', sg(:, 1), sg(:, 2), mL, mR, bp, sg(:, 3), sg(:, 4), ...
            'VariableNames', {'Seg', 'Start_s', 'End_s', 'Stim_L_mA', 'Stim_R_mA', 'Beta_dB', ...
            'BFMDRS', 'UHDRS'});
    end

    function onSegStim()
        i = curStream();
        if i == 0, return; end
        st_ = S.streams(i);
        if isempty(st_.stimT) || all(isnan(st_.stimT))
            uialert(fig, 'This recording has no stimulation data to segment.', 'Segments'); return;
        end
        if ~isempty(st_.segs)
            sel = uiconfirm(fig, 'Replace the existing segments for this recording?', 'Segments', ...
                'Options', {'Replace', 'Cancel'}, 'DefaultOption', 2);
            if ~strcmp(sel, 'Replace'), return; end
        end
        if strcmp(st_.hemi, 'R'), a = st_.stimR; else, a = st_.stimL; end
        t = st_.stimT(:);
        a = round(a(:) / 0.05) * 0.05;
        ok = ~isnan(t) & ~isnan(a);
        t = t(ok); a = a(ok);
        dur = numel(st_.x) / st_.fs;
        segs = zeros(0, 4);
        if numel(a) >= 2
            starts = find([true; diff(a) ~= 0]);
            ends = [starts(2:end) - 1; numel(a)];
            for q = 1:numel(starts)
                t1 = max(t(starts(q)), 0);
                t2 = min(t(ends(q)), dur);
                if t2 - t1 >= 5
                    segs(end+1, :) = [t1, t2, NaN, NaN]; %#ok<AGROW>
                end
            end
        end
        if isempty(segs)
            uialert(fig, 'No stable stimulation step of 5 s or longer was found.', 'Segments'); return;
        end
        S.streams(i).segs = segs;
        plotStreamStim();
        refreshSegTable();
        onSegPSD();                        % spectra per stimulation step, in a pop-out window
    end

    function onSegPSD()
        % Welch PSD of every segment of the selected recording, overlaid and
        % labelled by segment number, plus mean beta power per segment
        % against the segment's stimulation amplitude. 0.5 s is trimmed at
        % each segment edge to keep stimulation transitions out.
        i = curStream();
        if i == 0, return; end
        st_ = S.streams(i);
        sg = st_.segs;
        if isempty(sg)
            uialert(fig, 'Create segments first (Stim steps or Add view).', 'Segment PSDs'); return;
        end
        x = prepSignal(st_.x);
        fs = st_.fs;
        n = numel(x);
        L = round(max(efWin.Value, 1) * fs);
        band = [efBetaLo.Value efBetaHi.Value];
        fmax = min(100, fs / 2);
        nS = size(sg, 1);
        cm = tcolors(nS);
        % stimulation amplitude of the recorded hemisphere within each segment
        mA = nan(nS, 1);
        if ~isempty(st_.stimT)
            if strcmp(st_.hemi, 'R'), sv = st_.stimR; else, sv = st_.stimL; end
            for q = 1:nS
                in = st_.stimT >= sg(q, 1) & st_.stimT <= sg(q, 2);
                if any(in), mA(q) = median(sv(in), 'omitnan'); end
            end
        end
        useStim = any(~isnan(mA));
        fig2 = figure('Name', sprintf('Segment PSDs: %s %s %s', sessLabel(st_.fileIdx), ...
            st_.source, st_.channel), 'Color', 'w', 'NumberTitle', 'off', 'Position', [120 120 1250 500]);
        tl = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        ax1 = nexttile(tl); hold(ax1, 'on');
        ax2 = nexttile(tl); hold(ax2, 'on');
        used = []; skipped = []; xs = []; ys = [];
        for q = 1:nS
            a = max(1, round((sg(q, 1) + 0.5) * fs) + 1);
            b = min(n, round((sg(q, 2) - 0.5) * fs));
            if b - a + 1 < 2 * L
                skipped(end+1) = q; %#ok<AGROW>
                continue;
            end
            [P, f] = welchPSDn(x(a:b), fs, L);
            k = f >= 1 & f <= fmax;
            lbl = sprintf('#%d', q);
            if ~isnan(mA(q)), lbl = sprintf('#%d  %.2g mA', q, mA(q)); end
            sc = scoreText(sg(q, 3), sg(q, 4), true);
            if ~strcmp(sc, 'unscored'), lbl = [lbl ', ' sc]; end %#ok<AGROW>
            plot(ax1, f(k), P(k), '-', 'Color', cm(q, :), 'LineWidth', 1.4, 'DisplayName', lbl);
            inB = f >= band(1) & f <= band(2);
            fb = f(inB); pb = P(inB);
            [pk, j] = max(pb);
            text(ax1, fb(j), pk, sprintf(' #%d', q), 'Color', cm(q, :) * 0.8, 'FontWeight', 'bold', ...
                'FontSize', 9, 'VerticalAlignment', 'bottom', 'PickableParts', 'none');
            bdb = 10 * log10(mean(pb));
            if useStim, xq = mA(q); else, xq = q; end
            if ~isnan(xq)
                plot(ax2, xq, bdb, 'o', 'MarkerSize', 9, 'MarkerFaceColor', cm(q, :), ...
                    'MarkerEdgeColor', cm(q, :) * 0.7, 'DisplayName', sprintf('#%d', q));
                text(ax2, xq, bdb, sprintf('  #%d', q), 'FontSize', 9, 'PickableParts', 'none');
                xs(end+1) = xq; ys(end+1) = bdb; %#ok<AGROW>
            end
            used(end+1) = q; %#ok<AGROW>
        end
        if isempty(used)
            close(fig2);
            uialert(fig, sprintf(['Every segment is shorter than two %.1f-s Welch windows ' ...
                '(after trimming 0.5 s at each edge).'], L / fs), 'Segment PSDs');
            return;
        end
        if numel(xs) > 1
            plot(ax2, xs, ys, '-', 'Color', [0.7 0.7 0.7], 'HandleVisibility', 'off');   % segment order
        end
        hold(ax1, 'off'); hold(ax2, 'off');
        ax1.YScale = 'log';
        xlim(ax1, [1 fmax]);
        shadeBand(ax1, band(1), band(2));
        xlabel(ax1, 'Frequency (Hz)'); ylabel(ax1, 'PSD (a.u.^2/Hz)');
        title(ax1, sprintf('%s | %s %s: PSD per segment', sessLabel(st_.fileIdx), st_.source, ...
            st_.channel), 'Interpreter', 'none');
        if ~isempty(skipped)
            subtitle(ax1, sprintf('Skipped (too short): %s', strjoin(arrayfun(@(v) sprintf('#%d', v), ...
                skipped, 'UniformOutput', false), ', ')));
        end
        legend(ax1, 'Location', 'northeastoutside', 'Interpreter', 'none', 'Box', 'off');
        if useStim
            xlabel(ax2, sprintf('Stimulation, %s hemisphere (mA)', hemiName(st_.hemi)));
        else
            xlabel(ax2, 'Segment #');
        end
        ylabel(ax2, sprintf('Mean %g-%g Hz power (dB)', band));
        title(ax2, 'Beta power per segment (grey line = segment order)');
        grid(ax2, 'on');
        tipAxes([ax1 ax2]);
    end

    function onSegAdd()
        i = curStream();
        if i == 0, return; end
        dur = numel(S.streams(i).x) / S.streams(i).fs;
        xl = axStimSt.XLim;
        xl = [max(0, xl(1)), min(dur, xl(2))];
        if diff(xl) < 1
            uialert(fig, 'Zoom the spectrogram or stimulation panel to the period to annotate first.', ...
                'Segments'); return;
        end
        S.streams(i).segs(end+1, :) = [xl, NaN, NaN];
        plotStreamStim();
        refreshSegTable();
    end

    function onSegClear()
        i = curStream();
        if i == 0, return; end
        S.streams(i).segs = zeros(0, 4);
        plotStreamStim();
        refreshSegTable();
    end

    function onSegEdit(evt)
        i = curStream();
        if i == 0 || isempty(evt.Indices), return; end
        r = evt.Indices(1); c = evt.Indices(2);
        if r > size(S.streams(i).segs, 1), return; end
        v = double(evt.NewData);
        if c == 7, S.streams(i).segs(r, 3) = v; elseif c == 8, S.streams(i).segs(r, 4) = v; end
        plotStreamStim();
    end

%% ================================================================ Stats tab
    function [vals, labels, extra] = buildGroups(h, E, isEpoch)
        [dt, v, dtU] = getTL(h);
        extra = '';
        ep = assignEpoch(dtU, E);
        ep(~ismember(ep, selEpochs())) = NaN;      % ticked sessions only
        ok = ~isnan(v) & ~isnan(ep);
        if strcmp(ddUnit.Value, 'Daily median')
            if any(ok)
                day = datenum(dateshift(dt(ok), 'start', 'day'));
                [Gi, gEp] = findgroups(ep(ok), day);
                med = splitapply(@median, v(ok), Gi);
                cnt = splitapply(@numel,  v(ok), Gi);
                keepD = cnt / 144 >= spCov.Value;
                uEp = gEp(keepD); uV = med(keepD);
                extra = sprintf('  %d day(s) kept, %d dropped for coverage < %.0f %%', ...
                    sum(keepD), sum(~keepD), 100 * spCov.Value);
            else
                uEp = zeros(0, 1); uV = zeros(0, 1);
            end
        else
            uEp = ep(ok); uV = v(ok);
        end
        if isEpoch
            K = numel(E);
            vals = cell(1, K);
            for k = 1:K
                vals{k} = uV(uEp == k);
            end
            labels = {E.label};
        else
            [grp, thr, snm] = bfmGroups(E);
            g = grp(:);
            gU = nan(size(uEp));
            if ~isempty(uEp), gU = g(uEp); end
            vals = {uV(gU == 1), uV(gU == 2)};
            labels = {sprintf('Low %s (<%g)', snm, thr), sprintf('High %s (>=%g)', snm, thr)};
            if isnan(thr)
                extra = [extra newline sprintf(['  No %s scores in file names or manual entries ' ...
                    '(use "Edit scores...").'], snm)];
            else
                extra = [extra newline sprintf('  low: %s | high: %s', ...
                    strjoin({E(grp == 1).label}, ', '), strjoin({E(grp == 2).label}, ', '))];
            end
        end
    end

    function onRunStats()
        E = getEpochs();
        if isempty(E)
            uialert(fig, 'Load JSON files first.', 'Stats'); return;
        end
        hs = selHemis();
        isEpoch = strcmp(ddGroup.Value, 'Epochs (one per file)');
        unit = ddUnit.Value;
        grpName = ddGroup.Value;
        if ~isEpoch, grpName = sprintf('%s high vs low', ddScore.Value); end
        clearAxes(axStats); legend(axStats, 'off');
        hold(axStats, 'on');
        off = 0;
        if numel(hs) == 2, off = [-0.2 0.2]; end
        rs = RandStream('mt19937ar', 'Seed', 7);
        txt = {}; rows = cell(0, 8); allLabels = {};
        for i = 1:numel(hs)
            h = hs{i};
            c = hcol(h);
            [vals, labels, extra] = buildGroups(h, E, isEpoch);
            allLabels = labels;
            txt{end+1} = sprintf('==== %s | %s | %s ====', hemiName(h), grpName, unit); %#ok<AGROW>
            if ~isempty(extra), txt = [txt, strsplit(extra, newline)]; end %#ok<AGROW>
            for g = 1:numel(vals)
                y = vals{g};
                if isempty(y)
                    txt{end+1} = sprintf('  %-22s n = 0', labels{g}); %#ok<AGROW>
                    continue;
                end
                q = pctl(y, [25 50 75]);
                txt{end+1} = sprintf('  %-22s n = %5d  median %.4g  IQR [%.4g, %.4g]', ...
                    labels{g}, numel(y), q(2), q(1), q(3)); %#ok<AGROW>
                if isEpoch, gb_ = E(g).bfm; gu_ = E(g).uhdrs; else, gb_ = NaN; gu_ = NaN; end
                rows(end+1, :) = {hemiName(h), labels{g}, gb_, gu_, numel(y), q(2), q(1), q(3)}; %#ok<AGROW>
                xpos = g + off(i);
                boxchart(axStats, xpos * ones(numel(y), 1), y, 'BoxFaceColor', c, ...
                    'WhiskerLineColor', c, 'MarkerStyle', 'none', 'BoxWidth', 0.32, ...
                    'HandleVisibility', 'off');
                ys = y;
                if numel(ys) > 1500, ys = ys(randperm(rs, numel(ys), 1500)); end
                scatter(axStats, xpos + (rand(rs, numel(ys), 1) - 0.5) * 0.22, ys, 9, c, ...
                    'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
            end
            kept = find(~cellfun(@isempty, vals));
            if numel(kept) < 2
                txt = [txt, {'  Fewer than 2 non-empty groups: no test.', ''}]; %#ok<AGROW>
                continue;
            end
            G  = vals(kept);
            Gl = labels(kept);
            K  = numel(G);
            plot(axStats, kept + off(i), cellfun(@median, G), '-o', 'Color', c, ...
                'MarkerFaceColor', c, 'LineWidth', 1.2, 'DisplayName', [hemiName(h) ' medians']);
            if K == 2
                R = mannWhitney(G{2}, G{1});
                txt{end+1} = sprintf('  Mann-Whitney U (%s vs %s): U = %.1f, z = %.3f, p = %s', ...
                    Gl{2}, Gl{1}, R.U, R.z, fmtP(R.p)); %#ok<AGROW>
                txt{end+1} = sprintf('  Cliff''s delta = %.3f (%s; > 0: %s higher)', ...
                    R.delta, cliffLabel(R.delta), Gl{2}); %#ok<AGROW>
            else
                KW = kruskalWallis(G);
                txt{end+1} = sprintf('  Kruskal-Wallis H(%d) = %.3f, p = %s, epsilon^2 = %.3f', ...
                    KW.df, KW.H, fmtP(KW.p), KW.eps2); %#ok<AGROW>
                txt{end+1} = '  Dunn post hoc (Holm-adjusted):'; %#ok<AGROW>
                D = dunnHolm(G);
                for r = 1:size(D, 1)
                    txt{end+1} = sprintf('    %-18s vs %-18s z = %7.3f  p = %-9s p_adj = %s', ...
                        Gl{D(r, 1)}, Gl{D(r, 2)}, D(r, 3), fmtP(D(r, 4)), fmtP(D(r, 5))); %#ok<AGROW>
                end
            end
            if isEpoch && K >= 3
                JT = jonckheere(G, ddTrend.Value);
                txt{end+1} = sprintf('  Jonckheere-Terpstra (%s): J = %.1f, z = %.3f, p = %s', ...
                    lower(ddTrend.Value), JT.J, JT.z, fmtP(JT.p)); %#ok<AGROW>
                xr = repelem((1:K)', cellfun(@numel, G(:)));
                yr = vertcat(G{:});
                [b, ~, nUsed] = theilSen(xr, yr, 2000);
                base = median(G{1});
                txt{end+1} = sprintf('  Theil-Sen slope = %.4g per epoch step (%.1f %% of first-epoch median)%s', ...
                    b, 100 * b / base, ternary(nUsed < numel(yr), ...
                    sprintf(' [random subsample n = %d]', nUsed), '')); %#ok<AGROW>
                [rho, pr] = spearman(xr, yr);
                txt{end+1} = sprintf('  Spearman rho (epoch rank vs value) = %.3f, p = %s', rho, fmtP(pr)); %#ok<AGROW>
                txt{end+1} = '  (trend tests use epochs with data, in chronological order)'; %#ok<AGROW>
            end
            if strcmp(unit, '10-min samples')
                txt{end+1} = '  CAUTION: 10-min samples are autocorrelated; p-values are anti-conservative.'; %#ok<AGROW>
            end
            txt{end+1} = ''; %#ok<AGROW>
        end
        hold(axStats, 'off');
        nG = numel(allLabels);
        if nG > 0
            xlim(axStats, [0.4 nG + 0.6]);
            axStats.XTick = 1:nG;
            axStats.XTickLabel = allLabels;
            axStats.TickLabelInterpreter = 'none';
            xtickangle(axStats, 20);
        end
        axStats.YScale = ternary(chkLog.Value, 'log', 'linear');
        ylabel(axStats, sprintf('LFP power (%s)', lower(unit)));
        title(axStats, sprintf('%s | %s', grpName, unit));
        legend(axStats, 'Location', 'best', 'Box', 'off');
        tipAxes(axStats);
        taStats.Value = txt;
        S.statsText = txt;
        if isempty(rows)
            S.statsTable = table();
        else
            S.statsTable = cell2table(rows, 'VariableNames', ...
                {'Hemisphere', 'Group', 'BFMDRS', 'UHDRS', 'N', 'Median', 'Q1', 'Q3'});
        end
    end

    function onExportStats()
        if isempty(S.statsText)
            uialert(fig, 'Run the statistics first.', 'Export'); return;
        end
        [f, p] = uiputfile('*.csv', 'Save group summary', 'stats_summary.csv');
        figure(fig);
        if isequal(f, 0), return; end
        writetable(S.statsTable, fullfile(p, f));
        [~, b] = fileparts(f);
        fid = fopen(fullfile(p, [b '_results.txt']), 'w');
        fprintf(fid, '%s\n', S.statsText{:});
        fclose(fid);
        uialert(fig, sprintf('Saved %s and %s_results.txt', f, b), 'Export', 'Icon', 'success');
    end

    function onExportTab()
        d = uigetdir(pwd, 'Folder for PNG export');
        figure(fig);
        if isequal(d, 0), return; end
        tab = tg.SelectedTab;
        axs = findobj(tab, 'Type', 'axes');
        stamp = char(string(datetime('now'), 'yyyyMMdd_HHmmss'));
        for i = 1:numel(axs)
            exportgraphics(axs(i), fullfile(d, sprintf('%s_%s_%d.png', tab.Title, stamp, i)), ...
                'Resolution', 300);
        end
        uialert(fig, sprintf('Saved %d image(s) to %s', numel(axs), d), 'Export', 'Icon', 'success');
    end
end

%% ======================================================================
%% ============================ LOCAL FUNCTIONS ==========================
%% ======================================================================

% ------------------------------------------------------------- UI helpers
function place(c, r, col)
c.Layout.Row = r;
c.Layout.Column = col;
end

function tipAxes(axs, zName)
% Data tips in the plot's own units: rows are named after the axis labels,
% date axes (datenum) are shown as dates, and named series show their name.
if nargin < 2, zName = 'Value'; end
for ax = axs(:)'
    if ~isvalid(ax), continue; end
    xl = cleanLbl(ax.XLabel.String, 'X');
    yl = cleanLbl(ax.YLabel.String, 'Y');
    zl = cleanLbl(ax.ZLabel.String, zName);
    xDate = ax.XLim(1) > 7e5 && ax.XLim(2) < 8e5;
    yDate = ax.YLim(1) > 7e5 && ax.YLim(2) < 8e5;
    if xDate, xl = 'Time'; end
    if yDate, yl = 'Date'; end
    objs = findall(ax, '-property', 'DataTipTemplate');
    for h = objs(:)'
        try
            switch h.Type
                case {'line', 'stair', 'scatter'}
                    x = h.XData;
                    if xDate
                        r1 = dataTipTextRow(xl, datetime(x, 'ConvertFrom', 'datenum'), 'yyyy-MM-dd HH:mm');
                    else
                        r1 = dataTipTextRow(xl, 'XData', '%.4g');
                    end
                    rows = [r1; dataTipTextRow(yl, 'YData', '%.4g')];
                    if ~isempty(h.DisplayName) && ~startsWith(h.DisplayName, 'data')
                        rows(end+1, 1) = dataTipTextRow('Series', repmat({h.DisplayName}, size(x))); %#ok<AGROW>
                    end
                    h.DataTipTemplate.DataTipRows = rows;
                case 'surface'
                    [Xg, Yg] = meshgrid(h.XData, h.YData);
                    if yDate
                        ry = dataTipTextRow(yl, datetime(Yg, 'ConvertFrom', 'datenum'), 'dd-MMM-yyyy');
                    else
                        ry = dataTipTextRow(yl, Yg, '%.4g');
                    end
                    h.DataTipTemplate.DataTipRows = [dataTipTextRow(xl, Xg, '%.2f'); ry; ...
                        dataTipTextRow(zl, 'ZData', '%.4g')];
                case 'image'
                    try
                        h.DataTipTemplate.DataTipRows = [dataTipTextRow(xl, 'XData', '%.4g'); ...
                            dataTipTextRow(yl, 'YData', '%.4g'); dataTipTextRow(zName, 'CData', '%.4g')];
                    catch
                        r = h.DataTipTemplate.DataTipRows;
                        names = {xl, yl, zName};
                        for q = 1:min(numel(r), 3), r(q).Label = names{q}; end
                        h.DataTipTemplate.DataTipRows = r;
                    end
            end
        catch
            % leave MATLAB's default tip for anything unsupported
        end
    end
end
end

function s = cleanLbl(s, default)
if iscell(s), s = strjoin(s, ' '); end
s = regexprep(char(s), '[_^{}\\]', '');
if isempty(strtrim(s)), s = default; end
end

function clearAxes(ax)
% cla() skips objects with HandleVisibility 'off' (IQR lines, shading,
% epoch boundaries, box/scatter layers); allchild() includes them.
delete(allchild(ax));
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function c = hcol(h)
% Hemisphere colours taken from turbo: Left = blue end, Right = red-orange end.
t = turbo(256);
if strcmp(h, 'L'), c = t(39, :); else, c = t(218, :); end
end

function c = tcolors(n)
% n distinguishable colours sampled from turbo (extremes trimmed).
t = turbo(256);
n = max(1, round(n));
if n == 1
    c = t(128, :);
else
    c = t(round(linspace(0.08, 0.92, n) * 255) + 1, :);
end
end

function c = hcolSafe(h)
if isempty(h), c = [0.2 0.2 0.2]; else, c = hcol(h); end
end

function s = hemiName(h)
if strcmp(h, 'L')
    s = 'Left';
elseif strcmp(h, 'R')
    s = 'Right';
else
    s = '?';
end
end

function setDateTicks(ax)
xl = ax.XLim;
if xl(1) < 1e5, return; end           % no datenum data on this axis yet
if diff(xl) <= 2, fmt = 'dd-MMM HH:mm'; else, fmt = 'dd-MMM-yy'; end
ticks = linspace(xl(1), xl(2), 7);
ax.XTick = ticks;
ax.XTickLabel = cellstr(string(datetime(ticks, 'ConvertFrom', 'datenum'), fmt));
end

function h = toBack(h)
% Decorative shading (bands, epochs, bursts, segments) goes behind the data
% and ignores the mouse, so data tips always reach the plotted data.
try
    set(h, 'PickableParts', 'none', 'HitTest', 'off');
    ax = ancestor(h(1), 'axes');
    ch = ax.Children;
    keep = true(size(ch));
    for q = 1:numel(h), keep = keep & ch ~= h(q); end
    ax.Children = [ch(keep); h(:)];
catch
end
end

function shadeBand(ax, lo, hi)
yl = ax.YLim;
ylim(ax, yl);
toBack(patch(ax, [lo hi hi lo], [yl(1) yl(1) yl(2) yl(2)], [0.6 0.6 0.6], ...
    'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off'));
end

function [xg, vg] = insertGaps(x, v, maxGap)
% Insert NaN between samples separated by more than maxGap so lines break.
x = x(:); v = v(:);
if numel(x) < 2, xg = x; vg = v; return; end
brk = diff(x) > maxGap;
pos = (1:numel(x))' + [0; cumsum(brk)];
xg = nan(numel(x) + sum(brk), 1); vg = xg;
xg(pos) = x; vg(pos) = v;
end

function [m, q1, q3] = binStats(bin, v)
m  = accumarray(bin(:), v(:), [144 1], @median, NaN);
q1 = accumarray(bin(:), v(:), [144 1], @(z) pctl(z, 25), NaN);
q3 = accumarray(bin(:), v(:), [144 1], @(z) pctl(z, 75), NaN);
end

function ep = assignEpoch(dtU, E)
ep = nan(numel(dtU), 1);
for k = numel(E):-1:1
    ep(dtU(:) <= E(k).tEnd) = k;
end
end

% ------------------------------------------------------------- constructors
function F = emptyFiles()
F = struct('name', {}, 'path', {}, 'patientId', {}, 'bfm', {}, 'uhdrs', {}, ...
    'bfmMan', {}, 'uhdrsMan', {}, 'sessionDate', {}, ...
    'sens', {}, 'nL', {}, 'nR', {}, 'nEv', {}, 'nStr', {}, 'nMon', {}, 'nTD', {}, 'stim', {});
end

function E = emptyEvents()
E = struct('dt', {}, 'name', {}, 'fL', {}, 'pL', {}, 'fR', {}, 'pR', {}, 'file', {});
end

function St = emptyStreams()
St = struct('source', {}, 'channel', {}, 'hemi', {}, 'fs', {}, 't0', {}, 'x', {}, ...
    'foi', {}, 'file', {}, 'fileIdx', {}, 'tick0', {}, 'stimT', {}, 'stimL', {}, 'stimR', {}, ...
    'bfmMan', {}, 'uhdrsMan', {}, 'segs', {});
end

function M = emptyMontage()
M = struct('hemi', {}, 'contact', {}, 'f', {}, 'mag', {}, 'peakF', {}, 'peakMag', {}, ...
    'artifact', {}, 'file', {}, 'fileIdx', {});
end

function st = setFileIdx(st, fi)
for i = 1:numel(st)
    st(i).fileIdx = fi;
end
end

function T = emptyTL()
T = struct('dt', emptyUTC(), 'v', zeros(0, 1), 'amp', zeros(0, 1));
end

function d = emptyUTC()
d = datetime.empty(0, 1);
d.TimeZone = 'UTC';
end

function d = natUTC()
d = NaT;
d.TimeZone = 'UTC';
end

% ------------------------------------------------------------- JSON parsing
function P = parsePerceptFile(fpath)
data = jsondecode(fileread(fpath));
if ~isstruct(data) || ~isscalar(data)
    error('top level is not a JSON object');
end
[~, nm, ext] = fileparts(fpath);
F = emptyFiles();
F(1).name = [nm ext];
F.path = fpath;
pid = regexp(nm, 'DBS-\d+', 'match', 'once');
if isempty(pid)
    try
        pid = char(data.PatientInformation.Final.PatientId);
    catch
        pid = '';
    end
end
F.patientId = pid;
F.bfm  = parseBFM(nm);
F.uhdrs = parseUHDRS(nm);
F.bfmMan = NaN;
F.uhdrsMan = NaN;
F.sens = getSensingInfo(data);
try
    F.stim = getStimInfo(data);
catch
    F.stim = struct('group', 'n/a', 'L', emptyHemiStim(), 'R', emptyHemiStim(), ...
        'adaptive', {{}}, 'aDBS', 'parse error');
end

tl.L = emptyTL();
tl.R = emptyTL();
if isfield(data, 'DiagnosticData') && isfield(data.DiagnosticData, 'LFPTrendLogs')
    lt = data.DiagnosticData.LFPTrendLogs;
    if isfield(lt, 'HemisphereLocationDef_Left')
        [tl.L.dt, tl.L.v, tl.L.amp] = pullTrend(lt.HemisphereLocationDef_Left);
    end
    if isfield(lt, 'HemisphereLocationDef_Right')
        [tl.R.dt, tl.R.v, tl.R.amp] = pullTrend(lt.HemisphereLocationDef_Right);
    end
end

sd = natUTC();
if isfield(data, 'SessionDate')
    try
        sd = parsePerceptTime(data.SessionDate);
    catch
    end
end
if isnat(sd)
    allDt = [tl.L.dt; tl.R.dt];
    if ~isempty(allDt), sd = max(allDt); end
end
F.sessionDate = sd;
F.nL = numel(tl.L.v);
F.nR = numel(tl.R.v);

P.events   = parseEvents(data, F.name);
P.streams  = parseTD(data, {'BrainSenseTimeDomain', 'Streaming'; ...
    'IndefiniteStreaming', 'Indefinite'}, F.name, F.sens);
P.streams  = attachStim(P.streams, data);
P.surveyTD = parseTD(data, {'LfpMontageTimeDomain', 'SurveyTD'}, F.name, F.sens);
P.montage  = parseMontage(data, F.name);
F.nEv  = numel(P.events);
F.nStr = numel(P.streams);
F.nMon = numel(P.montage);
F.nTD  = numel(P.surveyTD);
P.file = F;
P.tl   = tl;
end

function [dt, v, amp] = pullTrend(hs)
% Pools DateTime / LFP / stim amplitude across all sub-fields of one
% hemisphere's LFPTrendLogs (struct-array or cell-array entries).
ds = strings(0, 1); v = zeros(0, 1); amp = zeros(0, 1);
fns = fieldnames(hs);
for i = 1:numel(fns)
    e = hs.(fns{i});
    if isstruct(e) && isfield(e, 'DateTime')
        ds  = [ds;  string({e.DateTime}')];               %#ok<AGROW>
        v   = [v;   fieldVec(e, 'LFP')];                   %#ok<AGROW>
        amp = [amp; fieldVec(e, 'AmplitudeInMilliAmps')];  %#ok<AGROW>
    elseif iscell(e)
        for j = 1:numel(e)
            r = e{j};
            if isstruct(r) && isfield(r, 'DateTime')
                ds(end+1, 1)  = string(r.DateTime);                   %#ok<AGROW>
                v(end+1, 1)   = getNum(r, 'LFP');                     %#ok<AGROW>
                amp(end+1, 1) = getNum(r, 'AmplitudeInMilliAmps');    %#ok<AGROW>
            end
        end
    end
end
dt = parsePerceptTime(ds);
end

function out = fieldVec(e, f)
n = numel(e);
if ~isfield(e, f), out = nan(n, 1); return; end
c = {e.(f)};
bad = cellfun(@(z) isempty(z) || ~isnumeric(z), c);
c(bad) = {NaN};
out = cellfun(@(z) double(z(1)), c(:));
end

function ev = parseEvents(data, fname)
ev = emptyEvents();
if ~isfield(data, 'DiagnosticData') || ~isfield(data.DiagnosticData, 'LfpFrequencySnapshotEvents')
    return;
end
raw = asCell(data.DiagnosticData.LfpFrequencySnapshotEvents);
for i = 1:numel(raw)
    e = raw{i};
    if ~isstruct(e) || ~isfield(e, 'DateTime'), continue; end
    r = emptyEvents();
    r(1).dt = parsePerceptTime(e.DateTime);
    nm = 'Unnamed';
    if isfield(e, 'EventName') && ~isempty(e.EventName), nm = char(e.EventName); end
    r.name = nm;
    r.file = fname;
    if isfield(e, 'LfpFrequencySnapshotEvents') && ~isempty(e.LfpFrequencySnapshotEvents)
        snap = e.LfpFrequencySnapshotEvents;
        if iscell(snap), snap = snap{1}; end
        [r.fL, r.pL] = snapHemi(snap, 'HemisphereLocationDef_Left');
        [r.fR, r.pR] = snapHemi(snap, 'HemisphereLocationDef_Right');
    end
    ev = [ev; r]; %#ok<AGROW>
end
end

function [f, p] = snapHemi(snap, hf)
f = []; p = [];
if ~isstruct(snap) || ~isfield(snap, hf), return; end
s = snap.(hf);
if iscell(s), s = s{1}; end
if isstruct(s) && isfield(s, 'FFTBinData') && isfield(s, 'Frequency')
    p = double(s.FFTBinData(:));
    f = double(s.Frequency(:));
    if numel(p) ~= numel(f), f = []; p = []; end
end
end

function st = parseTD(data, srcs, fname, sens)
% Time-domain recordings from the JSON fields in srcs(:,1), tagged srcs(:,2).
st = emptyStreams();
for i = 1:size(srcs, 1)
    [raw, ok] = fieldCI(data, srcs{i, 1});
    if ~ok, continue; end
    recs = asCell(raw);
    for j = 1:numel(recs)
        r = recs{j};
        if ~isstruct(r) || ~isfield(r, 'TimeDomainData'), continue; end
        s = emptyStreams();
        s(1).source = srcs{i, 2};
        ch = '';
        if isfield(r, 'Channel'), ch = regexprep(char(r.Channel), '^.*\.', ''); end
        s.channel = ch;
        if contains(upper(ch), 'LEFT')
            s.hemi = 'L';
        elseif contains(upper(ch), 'RIGHT')
            s.hemi = 'R';
        else
            s.hemi = '';
        end
        fs = getNum(r, 'SampleRateInHz');
        if isnan(fs), fs = 250; end
        s.fs = fs;
        t0 = natUTC();
        if isfield(r, 'FirstPacketDateTime')
            try
                t0 = parsePerceptTime(r.FirstPacketDateTime);
            catch
            end
        end
        s.t0 = t0;
        s.x = double(r.TimeDomainData(:));
        s.tick0 = NaN;
        [tm, okt] = fieldCI(r, 'TicksInMses');
        if okt && (ischar(tm) || isstring(tm))
            tv = str2double(strsplit(char(tm), ','));
            tv = tv(~isnan(tv));
            if ~isempty(tv), s.tick0 = tv(1); end
        elseif okt && isnumeric(tm) && ~isempty(tm)
            s.tick0 = double(tm(1));
        end
        s.stimT = []; s.stimL = []; s.stimR = [];
        s.bfmMan = NaN; s.uhdrsMan = NaN;
        s.segs = zeros(0, 4);              % [start_s end_s BFMDRS UHDRS]
        s.foi = NaN;
        if strcmp(s.hemi, 'L'), s.foi = sens.foiL; elseif strcmp(s.hemi, 'R'), s.foi = sens.foiR; end
        s.file = fname;
        st = [st; s]; %#ok<AGROW>
    end
end
end

function st = attachStim(st, data)
% Stimulation amplitude during BrainSense Streaming comes from BrainSenseLfp
% (Left/Right mA at ~2 Hz). Each time-domain channel is matched to the
% BrainSenseLfp record with the nearest FirstPacketDateTime and aligned on
% the device tick clock (TicksInMs vs. the stream's first TicksInMses).
[raw, ok] = fieldCI(data, 'BrainSenseLfp');
if ~ok || isempty(st), return; end
recs = asCell(raw);
L = struct('t0', {}, 'tick', {}, 'mL', {}, 'mR', {});
for i = 1:numel(recs)
    r = recs{i};
    if ~isstruct(r), continue; end
    [ld, okd] = fieldCI(r, 'LfpData');
    if ~okd, continue; end
    c = asCell(ld);
    n = numel(c);
    tk = nan(n, 1); mL = tk; mR = tk;
    for j = 1:n
        e = c{j};
        tk(j) = numCI(e, 'TicksInMs');
        [lv, okl] = fieldCI(e, 'Left');
        if okl, mL(j) = numCI(lv, 'mA'); end
        [rv, okr] = fieldCI(e, 'Right');
        if okr, mR(j) = numCI(rv, 'mA'); end
    end
    t0 = natUTC();
    s0 = charCI(r, 'FirstPacketDateTime');
    if ~isempty(s0)
        try
            t0 = parsePerceptTime(s0);
        catch
        end
    end
    L(end+1) = struct('t0', t0, 'tick', tk, 'mL', mL, 'mR', mR); %#ok<AGROW>
end
if isempty(L), return; end
lt = vertcat(L.t0);
for k = 1:numel(st)
    if ~strcmp(st(k).source, 'Streaming') || isnat(st(k).t0), continue; end
    [dmin, j] = min(abs(seconds(lt - st(k).t0)));
    if isempty(j) || isnan(dmin) || dmin > 120, continue; end
    tk = L(j).tick;
    n = numel(tk);
    dur = numel(st(k).x) / st(k).fs;
    if ~isnan(st(k).tick0) && ~all(isnan(tk))
        t = (tk - st(k).tick0) / 1000;
    else
        t = nan(n, 1);
    end
    if all(isnan(t)) || min(t) < -60 || max(t) > dur + 60
        if ~all(isnan(tk))
            t = (tk - tk(find(~isnan(tk), 1))) / 1000 + seconds(L(j).t0 - st(k).t0);
        else
            t = (0:n - 1)' / 2;          % BrainSenseLfp is sampled at 2 Hz
        end
    end
    st(k).stimT = t(:);
    st(k).stimL = L(j).mL(:);
    st(k).stimR = L(j).mR(:);
end
end

function s = scoreText(b, u, short)
% "BFMDRS 30, UHDRS 8"; short form "BFM 30" for plot labels.
if nargin < 3, short = false; end
parts = {};
if short, nb = 'BFM'; else, nb = 'BFMDRS'; end
if ~isnan(b), parts{end+1} = sprintf('%s %g', nb, b); end
if ~isnan(u), parts{end+1} = sprintf('UHDRS %g', u); end
if isempty(parts)
    if short, s = 'unscored'; else, s = 'no score'; end
else
    s = strjoin(parts, ', ');
end
end

function s = num2sBlank(v)
if isempty(v) || isnan(v), s = ''; else, s = sprintf('%g', v); end
end

function mt = parseMontage(data, fname)
% BrainSense Survey spectra (LFPMontage): one entry per contact pair.
% Field names are matched case-insensitively (exports use "LFPMontage").
mt = emptyMontage();
[raw, ok] = fieldCI(data, 'LFPMontage');
if ~ok
    % fallback: any top-level field containing "montage" but not "timedomain"
    fns = fieldnames(data);
    hit = find(contains(lower(fns), 'montage') & ~contains(lower(fns), 'timedomain'), 1);
    if isempty(hit), return; end
    raw = data.(fns{hit});
end
recs = asCell(raw);
for i = 1:numel(recs)
    r = recs{i};
    if ~isstruct(r), continue; end
    [f, okF]  = fieldCI(r, 'LFPFrequency');
    [mg, okM] = fieldCI(r, 'LFPMagnitude');
    if ~okF || ~okM, continue; end
    f = double(f(:)); mg = double(mg(:));
    if numel(f) ~= numel(mg) || isempty(f), continue; end
    m = emptyMontage();
    m(1).f = f;
    m.mag = mg;
    loc = charCI(r, 'Hemisphere');
    ch  = regexprep(charCI(r, 'SensingElectrodes'), '^.*\.', '');
    if contains(lower(loc), 'left') || contains(upper(ch), 'LEFT')
        m.hemi = 'L';
    elseif contains(lower(loc), 'right') || contains(upper(ch), 'RIGHT')
        m.hemi = 'R';
    else
        m.hemi = '';
    end
    m.contact = ch;
    [v, okV] = fieldCI(r, 'PeakFrequencyInHertz');
    m.peakF = NaN; if okV && isnumeric(v) && ~isempty(v), m.peakF = double(v(1)); end
    [v, okV] = fieldCI(r, 'PeakMagnitudeInMicroVolt');
    m.peakMag = NaN; if okV && isnumeric(v) && ~isempty(v), m.peakMag = double(v(1)); end
    m.artifact = regexprep(charCI(r, 'ArtifactStatus'), '^.*\.', '');
    m.file = fname;
    mt = [mt; m]; %#ok<AGROW>
end
end

function [v, ok] = fieldCI(s, name)
% Case-insensitive field access for jsondecode structs.
v = []; ok = false;
if ~isstruct(s) || isempty(s), return; end
fns = fieldnames(s);
i = find(strcmpi(fns, name), 1);
if isempty(i), return; end
v = s(1).(fns{i});
ok = true;
end

function c = charCI(s, name)
[v, ok] = fieldCI(s, name);
if ok && (ischar(v) || isstring(v)), c = char(v); else, c = ''; end
end

function st = getStimInfo(data)
% Stimulation settings of the active group at session end (Groups.Final),
% plus every field whose path matches adaptive / threshold / limit /
% capture / ramp. aDBS field names differ across firmware versions, so the
% raw matches are kept for inspection, and the aDBS flag only looks at
% fields under an "Adaptive..." name.
st = struct('group', 'n/a', 'L', emptyHemiStim(), 'R', emptyHemiStim(), ...
    'adaptive', {{}}, 'aDBS', 'not detected');
g = [];
[G, ok] = fieldCI(data, 'Groups');
if ok
    [fin, ok2] = fieldCI(G, 'Final');
    if ~ok2, [fin, ok2] = fieldCI(G, 'Initial'); end
    if ok2
        gc = activeGroups(fin);
        if ~isempty(gc), g = gc{1}; end
    end
end
if isstruct(g)
    gid = regexprep(charCI(g, 'GroupId'), '^.*\.', '');
    if ~isempty(gid), st.group = gid; end
    [ps, ok] = fieldCI(g, 'ProgramSettings');
    if ok
        rateTop = numCI(ps, 'RateInHertz');
        pwTop = numCI(ps, 'PulseWidthInMicroSecond');
        st.L = hemiStim(ps, 'Left', rateTop, pwTop);
        st.R = hemiStim(ps, 'Right', rateTop, pwTop);
        st.adaptive = deepFind(ps, 'adaptive|threshold|limit|capture|ramp', 'ProgramSettings', 0);
    end
end
fns = fieldnames(data);
for i = find(contains(lower(fns), 'adapt'))'
    st.adaptive = [st.adaptive, deepFind(data.(fns{i}), '.', fns{i}, 0)];
end
if numel(st.adaptive) > 80
    st.adaptive = [st.adaptive(1:80), {'... (truncated)'}];
end
isAd = ~cellfun(@isempty, regexpi(st.adaptive, 'adapt', 'once'));
if any(isAd)
    ad = st.adaptive(isAd);
    modeIdx = ~cellfun(@isempty, regexpi(ad, 'adapt[^=]*(mode|status|state|enable|active)[^=]*=', 'once'));
    if any(modeIdx)
        vals = regexprep(ad(modeIdx), '^.*=\s*', '');
        isOff = ~cellfun(@isempty, regexpi(vals, 'off|disable|none|false|^0$|inactive', 'once'));
        if any(~isOff), st.aDBS = 'ON? (see details)'; else, st.aDBS = 'off'; end
    else
        st.aDBS = 'adaptive fields present';
    end
end
end

function hs = emptyHemiStim()
hs = struct('amps', zeros(1, 0), 'rate', NaN, 'pw', NaN, 'contacts', '', 'nProg', 0);
end

function hs = hemiStim(ps, side, rateTop, pwTop)
hs = emptyHemiStim();
progs = {};
[h, ok] = fieldCI(ps, [side 'Hemisphere']);
if ok
    [pr, okp] = fieldCI(h, 'Programs');
    if okp, progs = asCell(pr); end
end
if isempty(progs)
    [sc, oks] = fieldCI(ps, 'SensingChannel');
    if oks
        scs = asCell(sc);
        for j = 1:numel(scs)
            if contains(lower(charCI(scs{j}, 'HemisphereLocation')), lower(side))
                progs{end+1, 1} = scs{j}; %#ok<AGROW>
            end
        end
    end
end
hs.nProg = numel(progs);
for j = 1:numel(progs)
    p = progs{j};
    a = numCI(p, 'AmplitudeInMilliAmps');
    if ~isnan(a), hs.amps(end+1) = a; end
    if isnan(hs.rate), hs.rate = numCI(p, 'RateInHertz'); end
    if isnan(hs.pw), hs.pw = numCI(p, 'PulseWidthInMicroSecond'); end
    if isempty(hs.contacts), hs.contacts = electrodeStr(p); end
end
if isnan(hs.rate), hs.rate = rateTop; end
if isnan(hs.pw), hs.pw = pwTop; end
end

function s = electrodeStr(p)
% e.g. "E1- Case+" from ElectrodeState entries.
s = '';
[es, ok] = fieldCI(p, 'ElectrodeState');
if ~ok, return; end
c = asCell(es);
parts = {};
for j = 1:numel(c)
    res = upper(charCI(c{j}, 'ElectrodeStateResult'));
    if contains(res, 'NEGATIVE')
        sg = '-';
    elseif contains(res, 'POSITIVE')
        sg = '+';
    else
        continue;
    end
    nm = regexprep(charCI(c{j}, 'Electrode'), '^.*\.', '');
    nm = regexprep(nm, '^(FourElectrodes|SensightElectrode|Electrode)_?', 'E');
    parts{end+1} = [nm sg]; %#ok<AGROW>
end
s = strjoin(parts, ' ');
end

function v = numCI(s, name)
[x, ok] = fieldCI(s, name);
v = NaN;
if ok && isnumeric(x) && ~isempty(x), v = double(x(1)); end
end

function lines = deepFind(s, pat, prefix, depth)
% Recursively list "path = value" for leaves whose path matches pat.
lines = {};
if depth > 6, return; end
if iscell(s)
    for i = 1:min(numel(s), 20)
        lines = [lines, deepFind(s{i}, pat, sprintf('%s{%d}', prefix, i), depth + 1)]; %#ok<AGROW>
    end
    return;
end
if ~isstruct(s)
    if ~isempty(regexpi(prefix, pat, 'once')), lines = {sprintf('%s = %s', prefix, valStr(s))}; end
    return;
end
if numel(s) > 1
    for i = 1:min(numel(s), 20)
        lines = [lines, deepFind(s(i), pat, sprintf('%s(%d)', prefix, i), depth + 1)]; %#ok<AGROW>
    end
    return;
end
fns = fieldnames(s);
for i = 1:numel(fns)
    lines = [lines, deepFind(s.(fns{i}), pat, [prefix '.' fns{i}], depth + 1)]; %#ok<AGROW>
end
end

function t = valStr(v)
if ischar(v) || isstring(v)
    t = char(v);
elseif (isnumeric(v) || islogical(v)) && isscalar(v)
    t = num2str(v);
elseif (isnumeric(v) || islogical(v)) && numel(v) <= 6
    t = mat2str(double(v(:)'), 4);
else
    t = sprintf('[%s %s]', class(v), mat2str(size(v)));
end
end

function s = ampStr(hs)
if isempty(hs.amps)
    s = 'n/a';
else
    s = strjoin(arrayfun(@(a) sprintf('%.2g', a), hs.amps, 'UniformOutput', false), '/');
end
end

function s = num2s(x)
if isempty(x) || isnan(x), s = 'n/a'; else, s = sprintf('%g', x); end
end

function sens = getSensingInfo(data)
% Sensing contact pair + FOI per hemisphere. Tries the active group in
% Groups.Final, then GroupHistory newest-first; first entry with a
% SensingChannel wins.
sens = struct('chL', 'n/a', 'foiL', NaN, 'chR', 'n/a', 'foiR', NaN);
cands = {};
try
    if isfield(data, 'Groups') && isfield(data.Groups, 'Final')
        cands = [cands; activeGroups(data.Groups.Final)];
    end
catch
end
try
    if isfield(data, 'GroupHistory')
        gh = asCell(data.GroupHistory);
        d = repmat(natUTC(), numel(gh), 1);
        for i = 1:numel(gh)
            try
                d(i) = parsePerceptTime(gh{i}.SessionDate);
            catch
            end
        end
        [~, o] = sort(d, 'descend', 'MissingPlacement', 'last');
        for i = o(:)'
            if isfield(gh{i}, 'Groups')
                cands = [cands; activeGroups(gh{i}.Groups)]; %#ok<AGROW>
            end
        end
    end
catch
end
for c = 1:numel(cands)
    try
        ps = cands{c}.ProgramSettings;
        if ~isfield(ps, 'SensingChannel'), continue; end
        scs = asCell(ps.SensingChannel);
        for j = 1:numel(scs)
            sc = scs{j};
            loc = char(sc.HemisphereLocation);
            ch  = regexprep(char(sc.Channel), '^.*\.', '');
            foi = NaN;
            if isfield(sc, 'SensingSetup') && isfield(sc.SensingSetup, 'FrequencyInHertz')
                foi = double(sc.SensingSetup.FrequencyInHertz);
            end
            if contains(loc, 'Left') && strcmp(sens.chL, 'n/a')
                sens.chL = ch; sens.foiL = foi;
            elseif contains(loc, 'Right') && strcmp(sens.chR, 'n/a')
                sens.chR = ch; sens.foiR = foi;
            end
        end
        if ~strcmp(sens.chL, 'n/a') || ~strcmp(sens.chR, 'n/a'), return; end
    catch
    end
end
end

function out = activeGroups(G)
gc = asCell(G);
isAct = false(numel(gc), 1);
for i = 1:numel(gc)
    isAct(i) = isstruct(gc{i}) && isfield(gc{i}, 'ActiveGroup') && isequal(gc{i}.ActiveGroup, true);
end
out = [gc(isAct); gc(~isAct)];
end

function c = asCell(x)
if iscell(x)
    c = x(:);
elseif isstruct(x)
    c = num2cell(x(:));
else
    c = {};
end
end

function v = getNum(r, f)
v = NaN;
if isfield(r, f) && ~isempty(r.(f)) && isnumeric(r.(f))
    v = double(r.(f)(1));
end
end

function dt = parsePerceptTime(s)
s = string(s);
s = s(:);
if isempty(s), dt = emptyUTC(); return; end
s = regexprep(s, '\.\d+', '');
s = erase(s, 'Z');
s = replace(s, 'T', ' ');
dt = datetime(s, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'UTC');
end

function bfm = parseBFM(nm)
% "BFMDS 49.5", "BFMDRS 7", "BFMDS_49_5", "bfmdrs-12" -> 49.5, 7, 49.5, 12
bfm = parseScore(nm, '(?:BFMDRS|BFMDS)');
end

function u = parseUHDRS(nm)
% "UHDRS 12", "UHDRS_12_5", "UHDRS-TMS 30", "UHDRS chorea 8" -> 12, 12.5, 30, 8
u = parseScore(nm, 'UHDRS(?:[\s_-]*(?:TMS|TCS|chorea))?');
end

function v = parseScore(nm, key)
v = NaN;
tok = regexpi(nm, [key '[\s_-]*(\d+(?:[._]\d+)?)'], 'tokens', 'once');
if ~isempty(tok)
    v = str2double(strrep(tok{1}, '_', '.'));
end
end

function x = prepSignal(x)
x = double(x(:));
x(isnan(x)) = 0;
x = detrend(x);
end

function pk = peakIn(f, P, band)
inB = f >= band(1) & f <= band(2);
if ~any(inB), pk = mean(band); return; end
fb = f(inB); pb = P(inB);
[~, j] = max(pb);
pk = fb(j);
end

function s = hhmm(h)
if isnan(h), s = 'n/a'; return; end
m = round(h * 60);
s = sprintf('%02d:%02d', mod(floor(m / 60), 24), mod(m, 60));
end

function C = cosinor(hrs, y)
% Single-component 24-h cosinor by least squares:
% y = MESOR + A*cos(2*pi*(t - acrophase)/24).
hrs = hrs(:); y = y(:);
ok = ~isnan(y) & ~isnan(hrs);
hrs = hrs(ok); y = y(ok);
C = struct('mesor', NaN, 'amp', NaN, 'acro', NaN, 'R2', NaN);
if numel(y) < 10, return; end
w = 2 * pi / 24;
X = [ones(size(hrs)), cos(w * hrs), sin(w * hrs)];
b = X \ y;
res = y - X * b;
C.mesor = b(1);
C.amp = hypot(b(2), b(3));
C.acro = mod(atan2(b(3), b(2)) / w, 24);
C.R2 = 1 - sum(res.^2) / sum((y - mean(y)).^2);
end

function T = tdTable(R)
bands = vertcat(R.band);
T = table({R.session}', {R.channel}', {R.hemi}', bands(:, 1), bands(:, 2), [R.peakF]', ...
    [R.betaPSD]', [R.thr]', [R.n]', [R.rate]', [R.meanDur]', [R.medDur]', [R.pctLong]', ...
    [R.pctTime]', [R.meanAmp]', 'VariableNames', {'Session', 'Channel', 'Hemi', 'BandLo', ...
    'BandHi', 'PeakHz', 'BetaPSD', 'Threshold', 'N', 'RatePerMin', 'MeanDurMs', ...
    'MedianDurMs', 'PctLong', 'PctTime', 'MeanAmp'});
end

function v = tdMetric(r, name)
switch name
    case 'Burst rate (/min)',       v = r.rate;
    case 'Mean duration (ms)',      v = r.meanDur;
    case '% long bursts (>400 ms)', v = r.pctLong;
    case '% time in burst',         v = r.pctTime;
    case 'Mean burst amplitude',    v = r.meanAmp;
    case 'Peak beta freq (Hz)',     v = r.peakF;
    otherwise,                      v = r.betaPSD;
end
end

function txt = fitSummary(R)
txt = {R.label; sprintf('Method   : %s', R.method)};
if isfield(R, 'bfm')
    txt{end+1, 1} = sprintf('Severity : %s', scoreText(R.bfm, R.uhdrs));
end
if strcmp(R.method, 'IRASA')
    txt = [txt; {
        sprintf('Fit range: %.1f-%.1f Hz (IRASA valid to %.1f Hz)', R.frange, R.fmaxValid)
        sprintf('Offset   : %.3f', R.offset)
        sprintf('Exponent : %.3f', R.exponent)
        sprintf('R^2 (power-law fit): %.3f', R.R2)
        sprintf('Beta peak: %.1f Hz, log10(total/aperiodic) = %.3f', R.betaCF, R.betaPW)}];
else
    txt = [txt; {sprintf('Fit range: %.1f-%.1f Hz', R.frange); sprintf('Offset   : %.3f', R.offset)}];
    if ~isnan(R.knee)
        txt = [txt; {sprintf('Knee     : %.3f (knee freq %.1f Hz)', R.knee, abs(R.knee)^(1 / R.exponent))}];
    end
    txt = [txt; {
        sprintf('Exponent : %.3f', R.exponent)
        sprintf('R^2 = %.3f, mean abs error = %.4f', R.R2, R.err)
        sprintf('Peaks    : %d', size(R.peaks, 1))}];
    for q = 1:size(R.peaks, 1)
        txt{end+1, 1} = sprintf('  CF %5.1f Hz   PW %.3f   BW %.1f Hz', R.peaks(q, :)); %#ok<AGROW>
    end
    txt{end+1, 1} = sprintf('Beta peak: CF %.1f Hz, PW %.3f, BW %.1f Hz', R.betaCF, R.betaPW, R.betaBW);
end
end

%% ==== NUMERIC HELPERS (base MATLAB only) ===============================

function y = fftResample(x, M)
% Band-limited resampling of x to M samples (zero-pad / truncate spectrum).
x = x(:); N = numel(x);
X = fft(x);
Y = zeros(M, 1);
if M >= N
    h = floor(N / 2);
    Y(1:h+1) = X(1:h+1);
    Y(M-(N-h-1)+1:M) = X(h+2:N);
else
    h = floor(M / 2);
    Y(1:h+1) = X(1:h+1);
    Y(M-(M-h-1)+1:M) = X(N-(M-h-1)+1:N);
end
y = real(ifft(Y)) * (M / N);
end

function R = irasa(x, fs, winSec, frange, band)
% IRASA (Wen & Liu 2016), YASA-style: Welch PSDs of the signal resampled
% by h and 1/h (same segment length), geometric mean, median over h.
x = x(:); N = numel(x);
hset = 1.1:0.05:1.9;
L = min(round(winSec * fs), floor(N / max(hset)));
[Ptot, f] = welchPSDn(x, fs, L);
A = zeros(numel(f), numel(hset));
for i = 1:numel(hset)
    h = hset(i);
    Pu = welchPSDn(fftResample(x, round(N * h)), fs * h, L);
    Pd = welchPSDn(fftResample(x, round(N / h)), fs / h, L);
    A(:, i) = sqrt(Pu .* Pd);
end
Pap = median(A, 2);
R.method = 'IRASA';
R.f = f; R.Ptot = Ptot; R.Pap = Pap;
R.fmaxValid = fs / (2 * max(hset));
R.frange = [frange(1), min(frange(2), R.fmaxValid)];
R.mask = f >= R.frange(1) & f <= R.frange(2) & Pap > 0 & Ptot > 0;
if sum(R.mask) < 4, error('Too few frequency bins in the fit range.'); end
lf = log10(f(R.mask)); lp = log10(Pap(R.mask));
c = polyfit(lf, lp, 1);
R.exponent = -c(1);
R.offset = c(2);
R.R2 = 1 - sum((lp - polyval(c, lf)).^2) / sum((lp - mean(lp)).^2);
ratio = log10(Ptot ./ Pap);
inB = R.mask & f >= band(1) & f <= band(2);
R.betaCF = NaN; R.betaPW = NaN;
if any(inB)
    fb = f(inB); rb = ratio(inB);
    [R.betaPW, j] = max(rb);
    R.betaCF = fb(j);
end
R.betaBW = NaN; R.knee = NaN; R.err = NaN; R.peaks = zeros(0, 3);
end

function R = fooofFit(f, P, frange, opt)
% Spectral parameterization following FOOOF 1.x (Donoghue et al. 2020):
% robust aperiodic fit, iterative Gaussian peak search on the flattened
% spectrum, edge/overlap peak removal, joint peak refit, aperiodic refit.
f = f(:); P = P(:);
k = f >= frange(1) & f <= frange(2) & P > 0 & isfinite(P) & f > 0;
f = f(k); y = log10(P(k));
if numel(f) < 8, error('Fewer than 8 frequency bins inside the fit range.'); end
knee = strcmp(opt.mode, 'knee');
% robust aperiodic fit
ap0 = apFitFn(f, y, knee, []);
fl = y - apEval(f, ap0, knee);
fl(fl < 0) = 0;
msk = fl <= pctl(fl, 0.025);
if sum(msk) < 3, msk = true(size(f)); end
apR = apFitFn(f(msk), y(msk), knee, ap0);
flat = y - apEval(f, apR, knee);
% iterative peak search
df = mean(diff(f));
stdLim = opt.pwl / 2;
G = zeros(0, 3);
fi = flat;
while size(G, 1) < opt.maxPeaks
    [mx, im] = max(fi);
    if mx <= opt.peakThr * std(fi) || mx <= opt.minHeight, break; end
    half = 0.5 * mx;
    le = find(fi(1:im-1) <= half, 1, 'last');
    ri = find(fi(im+1:end) <= half, 1, 'first');
    sides = [];
    if ~isempty(le), sides(end+1) = im - le; end %#ok<AGROW>
    if ~isempty(ri), sides(end+1) = ri; end %#ok<AGROW>
    if isempty(sides)
        gs = mean(stdLim);
    else
        gs = min(sides) * 2 * df / (2 * sqrt(2 * log(2)));
    end
    gs = min(max(gs, stdLim(1)), stdLim(2));
    G(end+1, :) = [f(im), mx, gs]; %#ok<AGROW>
    fi = fi - gaussSum(f, G(end, :));
end
% drop peaks too close to the fit-range edges, then overlapping peaks
if ~isempty(G)
    G = G(abs(G(:, 1) - f(1)) > G(:, 3) & abs(G(:, 1) - f(end)) > G(:, 3), :);
end
if size(G, 1) > 1
    G = sortrows(G, 1);
    drop = false(size(G, 1), 1);
    for j = 1:size(G, 1) - 1
        if G(j, 1) > G(j+1, 1) - 0.75 * G(j+1, 3)
            if G(j, 2) < G(j+1, 2), drop(j) = true; else, drop(j+1) = true; end
        end
    end
    G = G(~drop, :);
end
% joint refit of all Gaussians (bounded via clamping)
if ~isempty(G)
    n = size(G, 1);
    lb = [G(:, 1) - 3 * G(:, 3), zeros(n, 1), repmat(stdLim(1), n, 1)];
    ub = [G(:, 1) + 3 * G(:, 3), inf(n, 1), repmat(stdLim(2), n, 1)];
    clampG = @(p) min(max(reshape(p, n, 3), lb), ub);
    obj = @(p) sum((flat - gaussSum(f, clampG(p))).^2);
    o = optimset('Display', 'off', 'MaxFunEvals', 800 * numel(G), 'MaxIter', 800 * numel(G), ...
        'TolX', 1e-6, 'TolFun', 1e-10);
    G = clampG(fminsearch(obj, G(:), o));
end
peakFit = gaussSum(f, G);
apF = apFitFn(f, y - peakFit, knee, apR);
apV = apEval(f, apF, knee);
model = apV + peakFit;
R.method = ['FOOOF (' opt.mode ')'];
R.f = f; R.y = y; R.model = model; R.apFit = apV; R.peakFit = peakFit; R.flat = y - apV;
R.frange = frange;
R.offset = apF(1);
R.exponent = apF(end);
if knee, R.knee = apF(2); else, R.knee = NaN; end
c = corrcoef(y, model);
R.R2 = c(1, 2)^2;
R.err = mean(abs(y - model));
R.peaks = zeros(size(G, 1), 3);
for j = 1:size(G, 1)
    [~, ii] = min(abs(f - G(j, 1)));
    R.peaks(j, :) = [G(j, 1), peakFit(ii), 2 * G(j, 3)];
end
end

function y = gaussSum(f, G)
y = zeros(size(f));
for j = 1:size(G, 1)
    y = y + G(j, 2) * exp(-(f - G(j, 1)).^2 / (2 * G(j, 3)^2));
end
end

function ap = apFitFn(f, y, knee, init)
% Aperiodic fit in log10 power: fixed = linear in log10(f); knee = fminsearch.
lf = log10(f);
if ~knee
    c = polyfit(lf, y, 1);
    ap = [c(2), -c(1)];
    return;
end
if numel(init) ~= 3
    init = [y(1), 0, abs((y(end) - y(1)) / (lf(end) - lf(1)))];
end
% fminsearch can stall in the knee direction, so start from several knee
% frequencies (k = fk^exp) and keep the best fit.
o = optimset('Display', 'off', 'MaxFunEvals', 6000, 'MaxIter', 6000, 'TolX', 1e-8, 'TolFun', 1e-12);
obj = @(p) sum((y - apEval(f, p, true)).^2);
init = init(:)';
starts = init;
for fk = [1 3 10 30]
    starts(end+1, :) = [init(1) + init(3) * log10(fk), fk ^ init(3), init(3)]; %#ok<AGROW>
end
best = inf;
for q = 1:size(starts, 1)
    [pq, v] = fminsearch(obj, starts(q, :), o);
    if v < best, best = v; ap = pq; end
end
ap(2) = abs(ap(2));
end

function y = apEval(f, ap, knee)
if knee
    y = ap(1) - log10(abs(ap(2)) + f .^ ap(3));
else
    y = ap(1) - ap(2) * log10(f);
end
end

function q = pctl(x, p)
% Percentile with linear interpolation between order statistics (type 7).
x = sort(x(~isnan(x)));
n = numel(x);
if n == 0, q = nan(size(p)); return; end
pos = 1 + (n - 1) * p(:) / 100;
lo = floor(pos); hi = ceil(pos);
q = x(lo) + (pos - lo) .* (x(hi) - x(lo));
q = reshape(q, size(p));
end

function w = hannw(L)
w = 0.5 - 0.5 * cos(2 * pi * (0:L-1)' / L);    % periodic Hann
end

function y = fftBandpass(x, fs, f1, f2)
% Zero-phase FFT-domain band-pass with raised-cosine edges and 1-s
% reflection padding (reduces wrap-around and edge ringing).
x = x(:); n = numel(x);
pad = min(n - 1, round(fs));
xp = [flipud(x(2:pad+1)); x; flipud(x(end-pad:end-1))];
N = numel(xp);
f = (0:N-1)' * (fs / N);
f = min(f, fs - f);
tw = max(0.5, 0.15 * (f2 - f1));
g = double(f >= f1 & f <= f2);
lo = f >= f1 - tw & f < f1;
g(lo) = 0.5 * (1 - cos(pi * (f(lo) - (f1 - tw)) / tw));
hi = f > f2 & f <= f2 + tw;
g(hi) = 0.5 * (1 + cos(pi * (f(hi) - f2) / tw));
y = real(ifft(fft(xp) .* g));
y = y(pad+1:pad+n);
end

function z = analyticSignal(x)
x = x(:); n = numel(x);
h = zeros(n, 1);
if mod(n, 2) == 0
    h([1, n/2 + 1]) = 1;
    h(2:n/2) = 2;
else
    h(1) = 1;
    h(2:(n + 1)/2) = 2;
end
z = ifft(fft(x) .* h);
end

function [P, f] = welchPSD(x, fs, winSec)
[P, f] = welchPSDn(x, fs, round(winSec * fs));
end

function [P, f] = welchPSDn(x, fs, L)
% Welch PSD, Hann window of L samples, 50% overlap, one-sided density.
x = x(:);
L = min(L, numel(x));
hop = max(1, floor(L / 2));
w = hannw(L);
starts = 1:hop:(numel(x) - L + 1);
seg = x(starts + (0:L-1)');
seg = (seg - mean(seg, 1)) .* w;
P = mean(abs(fft(seg)).^2, 2) / (fs * sum(w.^2));
nf = floor(L / 2) + 1;
P = P(1:nf);
if mod(L, 2) == 0
    P(2:end-1) = 2 * P(2:end-1);
else
    P(2:end) = 2 * P(2:end);
end
f = (0:nf-1)' * fs / L;
end

function [P, f, t] = stftPower(x, fs, winSec, overlap)
x = x(:);
L = min(round(winSec * fs), numel(x));
hop = max(1, round(L * (1 - overlap)));
w = hannw(L);
starts = 1:hop:(numel(x) - L + 1);
seg = x(starts + (0:L-1)');
seg = (seg - mean(seg, 1)) .* w;
P = abs(fft(seg)).^2 / (fs * sum(w.^2));
nf = floor(L / 2) + 1;
P = P(1:nf, :);
P(2:end, :) = 2 * P(2:end, :);
f = (0:nf-1)' * fs / L;
t = (starts - 1 + L / 2) / fs;
end

function [xf, env, valid] = burstEnvelope(x, fs, band)
% Band-pass, Hilbert envelope smoothed over 200 ms; 1-s edges marked invalid.
n = numel(x);
xf  = fftBandpass(x, fs, band(1), band(2));
env = movmean(abs(analyticSignal(xf)), max(1, round(0.2 * fs)));
edge = min(round(fs), floor(n / 4));
valid = true(n, 1);
valid([1:edge, n-edge+1:n]) = false;
end

function B = detectBursts(env, valid, fs, thr, minDurMs)
above = env > thr & valid;
d = diff([false; above; false]);
s = find(d == 1);
e = find(d == -1) - 1;
dur = (e - s + 1) / fs * 1000;
keep = dur >= minDurMs;
B.s = s(keep); B.e = e(keep); B.dur = dur(keep);
B.amp = arrayfun(@(a, b) max(env(a:b)), B.s, B.e);
B.thr = thr;
B.rate = numel(B.s) / (sum(valid) / fs / 60);
B.pctTime = 100 * sum(B.e - B.s + 1) / sum(valid);
end

function B = betaBursts(x, fs, band, pct, minDurMs)
% Envelope-threshold bursts with a within-recording percentile threshold.
[xf, env, valid] = burstEnvelope(x, fs, band);
B = detectBursts(env, valid, fs, pctl(env(valid), pct), minDurMs);
B.xf = xf;
B.env = env;
end

function b = phaseBins(ph, nb)
b = min(nb, floor((ph(:) + pi) / (2 * pi) * nb) + 1);
b(b < 1) = 1;
end

function [MI, pdist] = tortMI(bin, amp, nb)
sums = accumarray(bin, amp(:), [nb 1]);
cnt  = accumarray(bin, 1, [nb 1]);
m = sums ./ max(cnt, 1);
pdist = m / sum(m);
p = max(pdist, eps);
MI = (log(nb) + sum(p .* log(p))) / log(nb);
end

function R = pacAnalysis(x, fs, phB, amB, nSurr)
% Tort modulation index with circular-shift surrogates (shift >= 1 s).
n = numel(x);
ph = angle(analyticSignal(fftBandpass(x, fs, phB(1), phB(2))));
am = abs(analyticSignal(fftBandpass(x, fs, amB(1), amB(2))));
edge = round(fs);
keep = (edge + 1):(n - edge);
ph = ph(keep); am = am(keep);
nb = 18;
b = phaseBins(ph, nb);
[R.MI, R.pdist] = tortMI(b, am, nb);
R.centers = (-pi + pi / nb) + (0:nb-1)' * (2 * pi / nb);
m = numel(am);
rs = RandStream('mt19937ar', 'Seed', 1);
minShift = round(fs);
sur = zeros(nSurr, 1);
if m > 2 * minShift + 1
    shifts = minShift + randi(rs, m - 2 * minShift, nSurr, 1);
    for i = 1:nSurr
        sur(i) = tortMI(b, circshift(am, shifts(i)), nb);
    end
    R.z = (R.MI - mean(sur)) / std(sur);
    R.p = (sum(sur >= R.MI) + 1) / (nSurr + 1);
else
    R.z = NaN; R.p = NaN;
end
end

function [r, tieSizes] = tiedRank(x)
% Average ranks for ties; also returns the sizes of tie groups (> 1).
x = x(:); n = numel(x);
[xs, idx] = sort(x);
newRun = [true; diff(xs) ~= 0];
starts = find(newRun);
ends = [starts(2:end) - 1; n];
runId = cumsum(newRun);
avg = (starts + ends) / 2;
r = zeros(n, 1);
r(idx) = avg(runId);
tieSizes = ends - starts + 1;
tieSizes = tieSizes(tieSizes > 1);
end

function R = mannWhitney(x, y)
% Two-sided Mann-Whitney U (normal approx., tie + continuity corrected).
% U counts pairs with x > y (+0.5 per tie); delta = Cliff's delta (x vs y).
x = x(:); y = y(:);
n1 = numel(x); n2 = numel(y); N = n1 + n2;
[r, t] = tiedRank([x; y]);
U = sum(r(1:n1)) - n1 * (n1 + 1) / 2;
mu = n1 * n2 / 2;
sig = sqrt(n1 * n2 / 12 * ((N + 1) - sum(t.^3 - t) / (N * (N - 1))));
R.U = U;
R.z = (U - mu - 0.5 * sign(U - mu)) / sig;
R.p = min(1, erfc(abs(R.z) / sqrt(2)));
R.delta = 2 * U / (n1 * n2) - 1;
end

function R = kruskalWallis(groups)
groups = cellfun(@(g) g(:), groups(:), 'UniformOutput', false);
ni = cellfun(@numel, groups);
k = numel(groups); N = sum(ni);
[r, t] = tiedRank(vertcat(groups{:}));
g = repelem((1:k)', ni);
Rs = accumarray(g, r);
H = 12 / (N * (N + 1)) * sum(Rs.^2 ./ ni) - 3 * (N + 1);
H = H / (1 - sum(t.^3 - t) / (N^3 - N));
R.H = H;
R.df = k - 1;
R.p = gammainc(H / 2, R.df / 2, 'upper');
R.eps2 = H / (N - 1);
end

function D = dunnHolm(groups)
% Rows: [i j z p p_Holm]
groups = cellfun(@(g) g(:), groups(:), 'UniformOutput', false);
ni = cellfun(@numel, groups);
k = numel(groups); N = sum(ni);
[r, t] = tiedRank(vertcat(groups{:}));
g = repelem((1:k)', ni);
Rbar = accumarray(g, r) ./ ni;
s2 = N * (N + 1) / 12 - sum(t.^3 - t) / (12 * (N - 1));
pr = nchoosek(1:k, 2);
z = (Rbar(pr(:, 1)) - Rbar(pr(:, 2))) ./ sqrt(s2 * (1 ./ ni(pr(:, 1)) + 1 ./ ni(pr(:, 2))));
p = erfc(abs(z) / sqrt(2));
D = [pr, z, p, holm(p)];
end

function padj = holm(p)
p = p(:); m = numel(p);
[ps, o] = sort(p);
adj = min(1, cummax((m - (1:m)' + 1) .* ps));
padj = zeros(m, 1);
padj(o) = adj;
end

function R = jonckheere(groups, direction)
% Jonckheere-Terpstra for ordered groups; tie-corrected variance
% (Hollander & Wolfe). J counts pairs where a later group exceeds an
% earlier one (+0.5 per tie).
groups = cellfun(@(g) g(:), groups(:), 'UniformOutput', false);
k = numel(groups);
ni = cellfun(@numel, groups);
N = sum(ni);
J = 0;
for a = 1:k-1
    for b = a+1:k
        r = tiedRank([groups{a}; groups{b}]);
        J = J + sum(r(ni(a)+1:end)) - ni(b) * (ni(b) + 1) / 2;
    end
end
[~, t] = tiedRank(vertcat(groups{:}));
mu = (N^2 - sum(ni.^2)) / 4;
A  = N * (N - 1) * (2 * N + 5) - sum(ni .* (ni - 1) .* (2 * ni + 5)) - sum(t .* (t - 1) .* (2 * t + 5));
Bv = sum(ni .* (ni - 1) .* (ni - 2)) * sum(t .* (t - 1) .* (t - 2)) / (36 * N * (N - 1) * (N - 2));
Cv = sum(ni .* (ni - 1)) * sum(t .* (t - 1)) / (8 * N * (N - 1));
V = A / 72 + Bv + Cv;
R.J = J;
R.z = (J - mu) / sqrt(V);
switch lower(direction)
    case 'increasing', R.p = 0.5 * erfc(R.z / sqrt(2));
    case 'decreasing', R.p = 0.5 * erfc(-R.z / sqrt(2));
    otherwise,         R.p = erfc(abs(R.z) / sqrt(2));
end
end

function [slope, intercept, nUsed] = theilSen(x, y, maxN)
x = x(:); y = y(:); n = numel(x);
if n > maxN
    rs = RandStream('mt19937ar', 'Seed', 1);
    id = randperm(rs, n, maxN);
    x = x(id); y = y(id); n = maxN;
end
nUsed = n;
[I, J] = find(triu(true(n), 1));
dx = x(J) - x(I);
ok = dx ~= 0;
slope = median((y(J(ok)) - y(I(ok))) ./ dx(ok));
intercept = median(y - slope * x);
end

function [rho, p] = spearman(x, y)
n = numel(x);
c = corrcoef(tiedRank(x), tiedRank(y));
rho = c(1, 2);
if abs(rho) >= 1
    p = 0;
else
    t = rho * sqrt((n - 2) / (1 - rho^2));
    p = betainc((n - 2) / (n - 2 + t^2), (n - 2) / 2, 0.5);
end
end

function s = fmtP(p)
if isnan(p)
    s = 'n/a';
elseif p < 1e-4
    s = '<1e-4';
else
    s = sprintf('%.4f', p);
end
end

function s = cliffLabel(d)
a = abs(d);
if a < 0.147
    s = 'negligible';
elseif a < 0.33
    s = 'small';
elseif a < 0.474
    s = 'medium';
else
    s = 'large';
end
end
