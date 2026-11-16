function app = WoZControl(varargin)
%WOZCONTROL Wizard-of-Oz control interface for the restaurant dialogue.
%
%   WoZControl                                   % local test: audio played by MATLAB
%   WoZControl('UE5Port',7000)                   % UE5 mode: UE5 plays audio + animation
%
%   The wizard listens to the participant and clicks the matching customer
%   intent. The GUI sends the waiter clip(s) to UE5 (and/or plays them locally),
%   moves to the next dialogue state and logs every action with timestamps.
%
%   Audio output ('AudioOutput'):
%     'matlab' - MATLAB plays audio/<clipID>.wav (TTS fallback: say on macOS, SAPI on Windows)
%     'ue5'    - MATLAB only sends commands; UE5 plays voice + face + body (default if UE5Port>0)
%     'both'   - both (debugging only; audio will be doubled)
%
%   TCP protocol: UE5 is the TCP server on UE5Host:UE5Port, MATLAB connects as client
%   (tcpclient = base MATLAB, no toolbox). One JSON object per line ("\n"-terminated).
%     MATLAB -> UE5
%       {"event":"play",    "clip":"W06_special","seq":12,"state":"ORDER",...}
%       {"event":"stop",    "seq":13}
%       {"event":"gesture", "name":"nod","seq":14}
%       {"event":"ping",    "seq":15}
%     UE5 -> MATLAB (same connection)
%       {"event":"started", "clip":"W06_special","seq":12}   optional
%       {"event":"done",    "clip":"W06_special","seq":12}   required: triggers next queued clip
%       {"event":"pong",    "seq":15}
%     If no "done" arrives within the expected clip duration + DoneTimeout seconds,
%     the next clip is sent anyway and a 'ue5_timeout' row is logged.
%
%   Keys: 1-9 intents, F fallback, R replay, S stop, Backspace undo,
%         Q W E A D Z X C = gesture buttons (in panel order).

p = inputParser;
here = fileparts(mfilename('fullpath'));
p.addParameter('AudioDir',   fullfile(here,'audio'));
p.addParameter('LogDir',     fullfile(here,'logs'));
p.addParameter('UE5Host',    '127.0.0.1');
p.addParameter('UE5Port',    0);
p.addParameter('AudioOutput','');
p.addParameter('DoneTimeout', 2.0);
p.addParameter('UseTTS',     true);
p.addParameter('ParticipantID', '');
p.parse(varargin{:});
cfg = p.Results;
if isempty(cfg.AudioOutput)
    if cfg.UE5Port > 0, cfg.AudioOutput = 'ue5'; else, cfg.AudioOutput = 'matlab'; end
end
cfg.AudioOutput = validatestring(cfg.AudioOutput, {'matlab','ue5','both'});
localAudio = any(strcmp(cfg.AudioOutput, {'matlab','both'}));
ueDriven   = any(strcmp(cfg.AudioOutput, {'ue5','both'})) && cfg.UE5Port > 0;

T = dialogueTree();
G = gestureList();

% ---------------- runtime state ----------------
st.state   = T.start;
st.dish    = '';
st.drink   = '';
st.history = {};
st.lastClips = {};
st.player  = [];
st.queue   = {};
st.t0      = tic;
st.conn    = [];
st.tts     = [];
st.seq     = 0;
st.pending = struct('seq',{},'clip',{},'tSent',{});   % play commands awaiting "done"
st.waitTimer = [];
st.ueOK    = false;

if isempty(cfg.ParticipantID)
    pid = inputdlg('Participant ID:','WoZ session',1,{'P01'});
    if isempty(pid), pid = {'P00'}; end
    cfg.ParticipantID = pid{1};
end
if ~exist(cfg.LogDir,'dir'), mkdir(cfg.LogDir); end
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
st.logFile = fullfile(cfg.LogDir, sprintf('%s_%s.csv', cfg.ParticipantID, stamp));
fid = fopen(st.logFile,'w');
fprintf(fid,'wallclock,t_sec,state,action,detail,clips,seq,latency_ms\n'); fclose(fid);

if localAudio && cfg.UseTTS && ispc
    try
        NET.addAssembly('System.Speech');
        st.tts = System.Speech.Synthesis.SpeechSynthesizer;
    catch
        st.tts = [];
    end
end

% ---------------- UI ----------------
fig = uifigure('Name',['WoZ Control - ' cfg.ParticipantID],'Position',[60 60 1250 720], ...
    'WindowKeyPressFcn',@onKey,'CloseRequestFcn',@onClose);
g = uigridlayout(fig,[1 2]); g.ColumnWidth = {'1x', 430};

left = uigridlayout(g,[6 1]);
left.RowHeight = {30, 50, 70, '1x', 110, 45};

top = uigridlayout(left,[1 2]); top.Padding = [0 0 0 0]; top.ColumnWidth = {'1x', 330};
lblState = uilabel(top,'FontSize',16,'FontWeight','bold');
lblUE = uilabel(top,'FontSize',12,'HorizontalAlignment','right');
lblTitle = uilabel(left,'FontSize',14,'WordWrap','on');
pnlSay = uipanel(left,'Title','Waiter is saying');
lblSay = uilabel(uigridlayout(pnlSay,[1 1]),'FontSize',14,'WordWrap','on','FontColor',[0 0.35 0.7],'Text','-');

pnlIntents = uipanel(left,'Title','Customer intent (click what the participant said)');
gridIntents = uigridlayout(pnlIntents,[4 3]);

pnlG = uipanel(left,'Title','Avatar gesture / expression (no speech)');
gridG = uigridlayout(pnlG,[2 ceil(numel(G)/2)]);
for gk = 1:numel(G)
    uibutton(gridG,'Text',sprintf('%s  %s',upper(G(gk).key),G(gk).label), ...
        'BackgroundColor',[.88 .92 1],'FontColor',[0 0 0],'ButtonPushedFcn',@(~,~)doGesture(gk));
end

bar = uigridlayout(left,[1 7]);
uibutton(bar,'Text','Fallback (F)','BackgroundColor',[1 .85 .6],'FontColor',[0 0 0],'ButtonPushedFcn',@(~,~)doFallback());
uibutton(bar,'Text','Replay (R)','ButtonPushedFcn',@(~,~)playClips(st.lastClips,'replay'));
uibutton(bar,'Text','Stop (S)','ButtonPushedFcn',@(~,~)stopAudio(true));
uibutton(bar,'Text','Undo (Bksp)','ButtonPushedFcn',@(~,~)doUndo());
uibutton(bar,'Text','Start session','BackgroundColor',[.7 .95 .7],'FontColor',[0 0 0],'ButtonPushedFcn',@(~,~)doRestart());
uibutton(bar,'Text','(Re)connect UE5','ButtonPushedFcn',@(~,~)connectUE5());
lblSlots = uilabel(bar,'Text','');

right = uigridlayout(g,[3 1]); right.RowHeight = {'1x', 30, 30};
tbl = uitable(right,'ColumnName',{'t [s]','state','action','detail','lat [ms]'}, ...
    'ColumnWidth',{50,70,85,'auto',55},'Data',cell(0,5));
edtNote = uieditfield(right,'Placeholder','Note for log (press Enter)', ...
    'ValueChangedFcn',@(s,~)addNote(s));
uilabel(right,'Text',['Log: ' st.logFile],'FontSize',10);

renderState();
logEvent('session','start',sprintf('audio=%s ue5=%s:%d', ...
    cfg.AudioOutput,cfg.UE5Host,cfg.UE5Port),{});
if cfg.UE5Port > 0, connectUE5(); else, updateUELabel(); end

app.fig = fig; app.tree = T; app.logFile = st.logFile; app.cfg = cfg;

% ================= dialogue logic =================
    function renderState()
        S = T.states.(st.state);
        lblState.Text = ['State: ' st.state];
        lblTitle.Text = S.title;
        lblSlots.Text = sprintf('dish: %s | drink: %s', dash(st.dish), dash(st.drink));
        delete(gridIntents.Children);
        n = numel(S.intents);
        gridIntents.RowHeight = repmat({'1x'},1,max(1,ceil(n/3)));
        for ii = 1:n
            uibutton(gridIntents,'Text',sprintf('%d  %s',ii,S.intents(ii).label), ...
                'FontSize',14,'WordWrap','on', ...
                'ButtonPushedFcn',@(~,~)chooseIntent(ii));
        end
    end

    function chooseIntent(k)
        S = T.states.(st.state);
        if k > numel(S.intents), return; end
        it = S.intents(k);
        st.history{end+1} = struct('state',st.state,'dish',st.dish,'drink',st.drink);
        prev = st.state;
        for s = 1:2:numel(it.set)
            st.(it.set{s}) = it.set{s+1};
        end
        clips = resolveClips(it.play);
        st.state = it.next;
        logEvent(prev,'intent',it.label,clips);
        playClips(clips,'play');
        renderState();
    end

    function doFallback()
        logEvent(st.state,'fallback','unsupported reply',{T.fallbackClip});
        playClips({T.fallbackClip},'play');
    end

    function doUndo()
        if isempty(st.history), return; end
        h = st.history{end}; st.history(end) = [];
        stopAudio(false);
        st.state = h.state; st.dish = h.dish; st.drink = h.drink;
        logEvent(st.state,'undo','',{});
        renderState();
    end

    function doRestart()
        st.state = T.start; st.dish = ''; st.drink = ''; st.history = {};
        logEvent(st.state,'start_dialogue','',T.startClips);
        playClips(T.startClips,'play');
        renderState();
    end

    function doGesture(k)
        sq = sendUE5(struct('event','gesture','name',G(k).name));
        logEvent(st.state,'gesture',G(k).name,{},sq);
    end

    function doPing()
        sq = sendUE5(struct('event','ping'));
        st.pending(end+1) = struct('seq',sq,'clip','__ping__','tSent',toc(st.t0));
    end

    function clips = resolveClips(play)
        clips = play;
        for q = 1:numel(clips)
            if strcmp(clips{q},'$CONFIRM')
                d = st.dish; if isempty(d), d = 'pasta'; end
                clips{q} = sprintf('C_%s_%s', d, dash2none(st.drink));
            end
        end
    end

% ================= clip playback / sequencing =================
    function playClips(clips, why)
        if isempty(clips), return; end
        stopAudio(false);
        st.lastClips = clips;
        st.queue = clips;
        if strcmp(why,'replay'), logEvent(st.state,'replay','',clips); end
        playNext();
    end

    function playNext()
        if isempty(st.queue) || ~isvalid(fig), return; end
        id = st.queue{1}; st.queue(1) = [];
        txt = '';
        if isKey(T.clips,id), txt = T.clips(id); end
        lblSay.Text = sprintf('[%s]  %s', id, txt);

        dur = clipDuration(id, txt);
        ueActive = ueDriven && ~isempty(st.conn);
        if ueActive
            sq = sendUE5(struct('event','play','clip',id,'state',st.state, ...
                'dish',st.dish,'drink',st.drink,'text',txt,'duration',dur));
            st.pending(end+1) = struct('seq',sq,'clip',id,'tSent',toc(st.t0));
            logEvent(st.state,'ue5_play',id,{},sq);
            armTimeout(sq, id, dur + cfg.DoneTimeout);   % UE5 "done" advances the queue
        end
        if localAudio
            playLocal(id, txt, ~ueActive);                 % local audio advances only if UE5 doesn't
        elseif ~ueActive
            playNext();
        end
    end

    function playLocal(id, txt, chain)
        f = fullfile(cfg.AudioDir,[id '.wav']);
        if isfile(f)
            [y,fs] = audioread(f);
            st.player = audioplayer(y,fs);
            play(st.player);
            % advance with a timer instead of StopFcn: on macOS StopFcn can fire
            % right after play(), which made the next clip start immediately
            if chain, armLocalTimer(size(y,1)/fs + 0.15); end
        elseif cfg.UseTTS && ismac
            system('killall say 2>/dev/null');
            system(['say "' strrep(txt,'"','') '" &']);
            if chain, armLocalTimer(clipDuration(id,txt)); end
        elseif ~isempty(st.tts)
            st.tts.SpeakAsyncCancelAll();
            st.tts.SpeakAsync(txt);
            if chain, armLocalTimer(clipDuration(id,txt)); end
        else
            fprintf('[WoZ] missing audio %s : %s\n', f, txt);
            if chain, playNext(); end
        end
    end

    function onLocalDone()
        if ~isempty(st.queue), playNext(); end
    end

    function d = clipDuration(id, txt)
        f = fullfile(cfg.AudioDir,[id '.wav']);
        if isfile(f)
            info = audioinfo(f); d = info.Duration;
        else
            d = 0.5 + 0.07*numel(txt);       % rough speech-length estimate
        end
    end

    function armTimeout(sq, id, secs)
        clearTimer();
        st.waitTimer = timer('StartDelay',round(secs,3),'TimerFcn',@(~,~)onTimeout(sq,id));
        start(st.waitTimer);
    end

    function armLocalTimer(secs)
        clearTimer();
        st.waitTimer = timer('StartDelay',round(secs,3),'TimerFcn',@(~,~)onLocalDone());
        start(st.waitTimer);
    end

    function clearTimer()
        if ~isempty(st.waitTimer) && isvalid(st.waitTimer)
            stop(st.waitTimer); delete(st.waitTimer);
        end
        st.waitTimer = [];
    end

    function onTimeout(sq, id)
        if ~isvalid(fig), return; end
        idx = find([st.pending.seq]==sq, 1);
        if isempty(idx), return; end                 % done already arrived
        st.pending(idx) = [];
        logEvent(st.state,'ue5_timeout',id,{},sq);
        st.ueOK = false; updateUELabel();
        playNext();
    end

    function stopAudio(logIt)
        st.queue = {};
        clearTimer();
        if ~isempty(st.player) && isplaying(st.player)
            st.player.StopFcn = '';
            stop(st.player);
        end
        if ~isempty(st.tts), st.tts.SpeakAsyncCancelAll(); end
        if ismac && localAudio, system('killall say 2>/dev/null'); end
        if ~isempty(st.pending)
            st.pending = st.pending(strcmp({st.pending.clip},'__ping__'));
            sendUE5(struct('event','stop'));
        end
        if logIt, logEvent(st.state,'stop','',{}); end
    end

% ================= TCP link to UE5 =================
    function connectUE5()
        if cfg.UE5Port <= 0, return; end
        if ~isempty(st.conn), try, configureCallback(st.conn,'off'); catch, end, end
        st.conn = []; st.ueOK = false;
        try
            c = tcpclient(cfg.UE5Host, cfg.UE5Port, 'ConnectTimeout', 3);
            configureTerminator(c, 'LF');
            configureCallback(c, 'terminator', @(src,~)onTcp(src));
            st.conn = c;
            logEvent(st.state,'ue5_connect','ok',{});
            doPing();
        catch err
            logEvent(st.state,'ue5_connect',['failed: ' err.message],{});
        end
        updateUELabel();
    end

    function sq = sendUE5(msg)
        sq = NaN;
        if isempty(st.conn), return; end
        st.seq = st.seq + 1; sq = st.seq;
        msg.seq = sq;
        msg.t = round(toc(st.t0),4);
        try
            writeline(st.conn, jsonencode(msg));
        catch err
            logEvent(st.state,'ue5_send_failed',err.message,{});
            st.conn = []; st.ueOK = false; updateUELabel();
        end
    end

    function onTcp(src)
        if ~isvalid(fig), return; end
        while src.NumBytesAvailable > 0
            line = strtrim(char(readline(src)));
            if isempty(line), continue; end
            try
                m = jsondecode(line);
            catch
                logEvent(st.state,'ue5_bad_msg',line,{}); continue
            end
            if ~isfield(m,'event'), continue; end
            sq = NaN; if isfield(m,'seq'), sq = m.seq; end
            clip = ''; if isfield(m,'clip'), clip = m.clip; end
            idx = find([st.pending.seq]==sq, 1);
            lat = NaN;
            if ~isempty(idx), lat = 1000*(toc(st.t0) - st.pending(idx).tSent); end
            st.ueOK = true; updateUELabel();
            switch m.event
                case 'started'
                    logEvent(st.state,'ue5_started',clip,{},sq,lat);
                case 'done'
                    logEvent(st.state,'ue5_done',clip,{},sq,lat);
                    if ~isempty(idx)
                        st.pending(idx) = [];
                        clearTimer();
                        playNext();
                    end
                case 'pong'
                    logEvent(st.state,'ue5_pong','',{},sq,lat);
                    if ~isempty(idx), st.pending(idx) = []; end
                otherwise
                    logEvent(st.state,['ue5_' m.event],clip,{},sq,lat);
            end
        end
    end

    function updateUELabel()
        if cfg.UE5Port <= 0
            lblUE.Text = 'UE5: off (local audio)'; lblUE.FontColor = [.4 .4 .4];
        elseif isempty(st.conn)
            lblUE.Text = sprintf('UE5: not connected  %s:%d',cfg.UE5Host,cfg.UE5Port); lblUE.FontColor = [.8 0 0];
        elseif st.ueOK
            lblUE.Text = sprintf('UE5: connected  %s:%d  (audio: %s)',cfg.UE5Host,cfg.UE5Port,cfg.AudioOutput);
            lblUE.FontColor = [0 .55 0];
        else
            lblUE.Text = sprintf('UE5: no reply  %s:%d  (audio: %s)',cfg.UE5Host,cfg.UE5Port,cfg.AudioOutput);
            lblUE.FontColor = [.85 .45 0];
        end
    end

% ================= logging =================
    function logEvent(state, action, detail, clips, sq, lat)
        if nargin < 5, sq = NaN; end
        if nargin < 6, lat = NaN; end
        t = toc(st.t0);
        wc = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));
        cl = strjoin(clips,'+');
        fid = fopen(st.logFile,'a');
        fprintf(fid,'%s,%.3f,%s,%s,"%s",%s,%s,%s\n', wc, t, state, action, ...
            strrep(detail,'"',''''), cl, num2strNaN(sq), num2strNaN(lat,'%.1f'));
        fclose(fid);
        if exist('tbl','var') && isvalid(tbl)
            tbl.Data = [{sprintf('%.2f',t), state, action, strtrim([detail ' ' cl]), num2strNaN(lat,'%.0f')}; tbl.Data];
        end
    end

    function addNote(src)
        if ~isempty(src.Value)
            logEvent(st.state,'note',src.Value,{});
            src.Value = '';
        end
    end

% ================= keyboard / close =================
    function onKey(~,evt)
        if isequal(fig.CurrentObject, edtNote), return; end
        k = evt.Key;
        if isscalar(k) && k>='1' && k<='9'
            chooseIntent(str2double(k));
        elseif strncmp(k,'numpad',6)
            chooseIntent(str2double(k(end)));
        else
            gi = find(strcmp({G.key},k),1);
            if ~isempty(gi), doGesture(gi); return; end
            switch k
                case 'f', doFallback();
                case 'r', playClips(st.lastClips,'replay');
                case 's', stopAudio(true);
                case 'backspace', doUndo();
            end
        end
    end

    function onClose(~,~)
        stopAudio(false);
        logEvent(st.state,'session','end',{});
        if ~isempty(st.conn), try, configureCallback(st.conn,'off'); catch, end, end
        st.conn = [];
        delete(fig);
    end
end

% ---------------- helpers ----------------
function G = gestureList()
% name = what UE5 receives; key = keyboard shortcut. Edit freely.
G = struct('name',{'nod','shake_head','smile','listen','think','point_menu','wave','idle'}, ...
           'label',{'Nod','Shake head','Smile','Listen','Think','Point at menu','Wave','Back to idle'}, ...
           'key',{'q','w','e','a','d','z','x','c'});
end
function s = dash(x),      if isempty(x), s = '-';    else, s = x; end, end
function s = dash2none(x), if isempty(x), s = 'none'; else, s = x; end, end
function s = num2strNaN(x, fmt)
if nargin < 2, fmt = '%d'; end
if isempty(x) || isnan(x), s = ''; else, s = sprintf(fmt, x); end
end
