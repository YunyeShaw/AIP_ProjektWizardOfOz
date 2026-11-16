function ue5Simulator(action, port)
%UE5SIMULATOR Start/stop the fake UE5 TCP endpoint (ue5_simulator.py) in the background.
%   ue5Simulator('start')        % port 7000, then: WoZControl('UE5Port',7000)
%   ue5Simulator('stop')
if nargin < 1, action = 'start'; end
if nargin < 2, port = 7000; end
here = fileparts(mfilename('fullpath'));
py = fullfile(here,'ue5_simulator.py');
if ispc
    stopCmd = 'taskkill /F /FI "WINDOWTITLE eq ue5sim*" >NUL 2>&1';
else
    stopCmd = sprintf('pkill -f "ue5_simulator.py %d" 2>/dev/null', port);
end
system(stopCmd);
if strcmp(action,'start')
    logf = fullfile(here,'logs','ue5_simulator.log');
    if ispc
        system(sprintf('start "ue5sim" /B python "%s" %d > "%s" 2>&1', py, port, logf));
    else
        system(sprintf('python3 "%s" %d > "%s" 2>&1 &', py, port, logf));
    end
    pause(0.7);
    fprintf('[UE5 sim] started on port %d (log: %s)\n', port, logf);
end
end
