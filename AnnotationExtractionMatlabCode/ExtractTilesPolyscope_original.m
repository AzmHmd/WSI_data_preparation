%addpath('openslide-matlab-master')
function ExtractTilesPolyscope_original(ImagePath, AnnotationPath, PatchPath, LabelMap, TileSize, DaTile)

%EXTRACTPATCHESPOLYSCOPE Summary of this function goes here
%   Detailed explanation goes here

Size = wsi_size(ImagePath);

if nargin < 5
    TileSize = [2000 2000];
end

if nargin < 6
    DaTile = true;
end


ImageSize = wsi_size(ImagePath);
%    ImageSize2 = reshape(wsi_size(ImagePath), [], 1);
ImageSize3 = ImageSize';

TileGrid = ceil(ImageSize./TileSize);

annotationText = fileread(AnnotationPath);
annotationText = regexprep(annotationText, '[\[()\]]', '');
lines = textscan(annotationText, '%s', 'Delimiter', '\n');

annotations = cellfun(@(x) split(x, ','), lines{1}, 'UniformOutput', false);
annotationTypes = cellfun(@(x) str2double(x(3)), annotations);
annotationActive = cellfun(@(x) str2double(x(1)), annotations);

annotations = annotations(annotationTypes==4 & annotationActive==1);

annotationColour = cellfun(@(x) x(end-2), annotations);
colours = unique(annotationColour);

if nargin < 4
    LabelMap = containers.Map(colours, colours);
else
    isValidColour = isKey(LabelMap, colours);
    invalidColours = colours(~isValidColour);
    
    if ~isempty(invalidColours)
        warning('Warning: The following annotation colours are present in the annotation file, but are missing in the provided labelMap:\n%s\n%s', strjoin(invalidColours, ', '), 'Annotations with these colours will be skipped.');
        
        isValidAnnotation = isKey(LabelMap, annotationColour);
        annotations = annotations(isValidAnnotation);
        annotationColour = annotationColour(isValidAnnotation);
        colours = colours(isValidColour);
    end
end

labels = cellfun(@(x) LabelMap(x), colours, 'UniformOutput', false);

for i=1:length(colours)
    mkdir(fullfile(PatchPath, labels{i}));
    
    for x=0:(TileGrid(1)-1)
        for y=0:(TileGrid(2)-1)
            %                 currentTileSize = min(TileSize([2 1]), ImageSize([2 1])-([y x].*TileSize([2 1])));
            currentTileSize = min(TileSize([2 1]), ImageSize3([2 1])-([y x].*TileSize([2 1])));
            
            if DaTile
                imwrite(zeros(currentTileSize), fullfile(PatchPath, labels{i}, ['Da' num2str(x + (y*TileGrid(1))) '.png']));
            else
                imwrite(zeros(currentTileSize), fullfile(PatchPath, labels{i}, [num2str(x) '_' num2str(y) '.png']));
            end
        end
    end
end

coords = cellfun(@(x) reshape(str2double(x(4:end-3))*Size(1), 2, [])', annotations, 'UniformOutput', false);
padding = [100 100 100 100];

for i=1:length(coords)
    bounds = {[floor(min(coords{i}(:, 2)))-padding(1) ceil(max(coords{i}(:, 2)))+padding(2)] [floor(min(coords{i}(:, 1)))-padding(3) ceil(max(coords{i}(:, 1)))+padding(4)]};
    
    shiftedCoords = [coords{i}(:, 1)-bounds{2}(1)+1 coords{i}(:, 2)-bounds{1}(1)+1];
    interpolatedCoords = round(pathLengthParameterisationSLAM(shiftedCoords, 'pathLength', 0.5));
    
    regionMask = false(bounds{1}(2)-bounds{1}(1)+1, bounds{2}(2)-bounds{2}(1)+1);
    regionMask(sub2ind(size(regionMask), interpolatedCoords(:, 2), interpolatedCoords(:, 1))) = true;
    regionMask = imfill(regionMask, 'holes');
    
    %if nnz(regionMask) > 10
    tileRangeX = floor(bounds{2}./2000);
    tileRangeY = floor(bounds{1}./2000);
    
    for u=tileRangeX(1):tileRangeX(2)
        for v=tileRangeY(1):tileRangeY(2)
            if DaTile
                maskPath = fullfile(PatchPath, LabelMap(annotationColour{i}), ['Da' num2str(u + (v*TileGrid(1))) '.png']);
            else
                maskPath = fullfile(PatchPath, LabelMap(annotationColour{i}), [num2str(u) '_' num2str(v) '.png']);
            end
            
            if exist(maskPath, 'file')
                tilePosition = [v u].*TileSize([2 1]);
                annotationPosition = [[bounds{1}(1) bounds{2}(1)]-tilePosition+1; [bounds{1}(2) bounds{2}(2)]-tilePosition+1];
                annotationRegion = [max(1, 2-annotationPosition(1, :)); size(regionMask)-max(0, annotationPosition(2, :)-TileSize([2 1]))];
                annotationPosition = [max(1, annotationPosition(1, :)); min(TileSize([2 1]), annotationPosition(2, :))];
                
                subMask = regionMask(annotationRegion(1, 1):annotationRegion(2, 1), annotationRegion(1, 2):annotationRegion(2, 2));
                
                if nnz(subMask) > 0
                    mask = im2double(imread(maskPath));
                    mask(annotationPosition(1, 1):annotationPosition(2, 1), annotationPosition(1, 2):annotationPosition(2, 2)) = max(mask(annotationPosition(1, 1):annotationPosition(2, 1), annotationPosition(1, 2):annotationPosition(2, 2)), subMask);
                    imwrite(mask, maskPath);
                end
            end
        end
    end
    %end
end
end

