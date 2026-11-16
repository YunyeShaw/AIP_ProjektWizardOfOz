function exportClipList(outFile)
%EXPORTCLIPLIST Write a recording script (clipID, text) for all waiter clips.
if nargin < 1, outFile = 'clip_list.csv'; end
T = dialogueTree();
k = sort(keys(T.clips));
fid = fopen(outFile,'w'); fprintf(fid,'clip_id,text\n');
for i = 1:numel(k), fprintf(fid,'%s,"%s"\n', k{i}, T.clips(k{i})); end
fclose(fid);
fprintf('%d clips -> %s (record each as audio/<clip_id>.wav)\n', numel(k), outFile);
end
