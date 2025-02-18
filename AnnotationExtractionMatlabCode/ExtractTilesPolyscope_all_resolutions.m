function ExtractTilesPolyscope_all_resolutions(ImagePath, AnnotationPath, PatchPath, LabelMap, TileSize, Resolution, DaTile, CreateBlanks)
%EXTRACTPATCHESPOLYSCOPE Summary of this function goes here
%   Detailed explanation goes here

if nargin < 5
    TileSize = [2000 2000];
end

if nargin < 6
    Resolution = 1;
end

if nargin < 7
    DaTile = true;
end

if nargin < 8
    CreateBlanks = false;
end

ImageSize = reshape(wsi_size(ImagePath), 1, [])*2.^(-Resolution);

TileGrid = ceil(ImageSize./TileSize);

annotationText = fileread(AnnotationPath);
annotationText = regexprep(annotationText, '[\[()\]]', '');
lines = textscan(annotationText, '%s', 'Delimiter', '\n');

annotations = cellfun(@(x) split(x, ','), lines{1}, 'UniformOutput', false);
annotationTypes = cellfun(@(x) str2double(x(3)), annotations);
annotationActive = cellfun(@(x) str2double(x(1)), annotations);

% specify which type of annotations to be selected: free-hand and
% rectangles
annotations = annotations((annotationTypes==4 | annotationTypes==2) & annotationActive==1);
annotationTypes = annotationTypes((annotationTypes==4 | annotationTypes==2) & annotationActive==1);

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
        %           annotations = annotations(isValidAnnotation);
        annotations = annotations(isValidAnnotation);
        annotationTypes = annotationTypes(isValidAnnotation);
        
        annotationColour = annotationColour(isValidAnnotation);
        colours = colours(isValidColour);
    end
end

labels = cellfun(@(x) LabelMap(x), colours, 'UniformOutput', false);

if CreateBlanks
    for i=1:length(colours)
        mkdir(fullfile(PatchPath, labels{i}));
        mkdir(fullfile(strrep(PatchPath,'10x','1x'), labels{i}));
        mkdir(fullfile(strrep(PatchPath,'10x','20x'), labels{i}));
%         mkdir(fullfile(strrep(PatchPath,'10x','40x'), labels{i}));
        
        for x=0:(TileGrid(1)-1)
            for y=0:(TileGrid(2)-1)
                currentTileSize = min(TileSize([2 1]), ImageSize([2 1])-([y x].*TileSize([2 1])));
                
                if DaTile
                    imwrite(zeros(currentTileSize), fullfile(PatchPath, labels{i}, ['Da' num2str(x + (y*TileGrid(1))) '.png']));
                else
                    imwrite(zeros(currentTileSize), fullfile(PatchPath, labels{i}, [num2str(x) '_' num2str(y) '.png']));
                end
            end
        end
    end
end

coords = cellfun(@(x) reshape(str2double(x(4:end-3))*ImageSize(1), 2, [])', annotations, 'UniformOutput', false);
% this line is added to extract the rectangles
coords(annotationTypes==2) = cellfun(@(x) [x(1, 1) x(1, 2); x(1, 1) x(2, 2); x(2, 1) x(2, 2); x(2, 1) x(1, 2)], coords(annotationTypes==2), 'UniformOutput', false);
padding = [100 100 100 100];

for i=1:length(coords)
    bounds = {[floor(min(coords{i}(:, 2)))-padding(1) ceil(max(coords{i}(:, 2)))+padding(2)] [floor(min(coords{i}(:, 1)))-padding(3) ceil(max(coords{i}(:, 1)))+padding(4)]};
    
    shiftedCoords = [coords{i}(:, 1)-bounds{2}(1)+1 coords{i}(:, 2)-bounds{1}(1)+1];
    interpolatedCoords = round(pathLengthParameterisationSLAM(shiftedCoords, 'pathLength', 0.5));
    
    regionMask = false(bounds{1}(2)-bounds{1}(1)+1, bounds{2}(2)-bounds{2}(1)+1);
    regionMask(sub2ind(size(regionMask), interpolatedCoords(:, 2), interpolatedCoords(:, 1))) = true;
    regionMask = imfill(regionMask, 'holes');
    
    %if nnz(regionMask) > 10
    tileRangeX = max(min(floor(bounds{2}./TileSize(1)),TileGrid(1)), 0);
    tileRangeY = max(min(floor(bounds{1}./TileSize(2)),TileGrid(2)), 0);
    
    for u=tileRangeX(1):tileRangeX(2)
        for v=tileRangeY(1):tileRangeY(2)
            patchFolder = fullfile(PatchPath, LabelMap(annotationColour{i}));
            
            if ~isfolder(patchFolder)
                mkdir(patchFolder);
                mkdir(strrep(patchFolder,'10x','1x'));
                mkdir(strrep(patchFolder,'10x','20x'));
                %mkdir(strrep(patchFolder,'10x','40x'));
            end
            
            if DaTile
                maskPath = fullfile(patchFolder, ['Da' num2str(u + (v*TileGrid(1))) '.png']);
            else
                maskPath = fullfile(patchFolder, [num2str(u) '_' num2str(v) '.png']);
            end
            
            tilePosition = [v u].*TileSize([2 1]);
            currentTileSize = min(TileSize([2 1]), ImageSize([2 1])-([v u].*TileSize([2 1])));
            
            if DaTile
                imageTilePath = fullfile(patchFolder, ['Da' num2str(u + (v*TileGrid(1))) 'T.png']);
            else
                imageTilePath = fullfile(patchFolder, [num2str(u) '_' num2str(v) 'T.png']);
            end
            
            if ~isfile(imageTilePath) 
%                 tilePosition = tilePosition+[0 -30];
                tile1x = imread_wsi(ImagePath, 'ReductionLevel', 3, 'PixelRegion',...
                    {[tilePosition(1)/2+1 tilePosition(1)/2+currentTileSize(1)/2], [tilePosition(2)/2+1 tilePosition(2)/2+currentTileSize(2)/2]});
%                 figure;imshow(tile1x)
                imwrite(tile1x, strrep(imageTilePath,'10x','1x'));
                
                tile10x = imread_wsi(ImagePath, 'ReductionLevel', 2, 'PixelRegion',...
                    {[tilePosition(1)+1 tilePosition(1)+currentTileSize(1)], [tilePosition(2)+1 tilePosition(2)+currentTileSize(2)]});
%                 figure;imshow(tile10x)
                imwrite(tile10x, imageTilePath);
                
                tile20x = imread_wsi(ImagePath, 'ReductionLevel', 1, 'PixelRegion',...
                    {[2*tilePosition(1)+1 2*tilePosition(1)+2*currentTileSize(1)], [2*tilePosition(2)+1 2*tilePosition(2)+2*currentTileSize(2)]});
%                 figure;imshow(tile20x)
                imwrite(tile20x, strrep(imageTilePath,'10x','20x'));
                
%                 tile40x = imread_wsi(ImagePath, 'ReductionLevel', 0, 'PixelRegion',...
%                     {[4*tilePosition(1)+1 4*tilePosition(1)+4*currentTileSize(1)], [4*tilePosition(2)+1 4*tilePosition(2)+4*currentTileSize(2)]});
% %                 figure;imshow(tile40x)
%                 imwrite(tile40x, strrep(imageTilePath,'10x','40x'));
%                  tilePosition = tilePosition+[0 50];
            end
            
            annotationPosition = [[bounds{1}(1) bounds{2}(1)]-tilePosition+1; [bounds{1}(2) bounds{2}(2)]-tilePosition+1];
            annotationRegion = [max(1, 2-annotationPosition(1, :)); size(regionMask)-max(0, annotationPosition(2, :)-TileSize([2 1]))];
            annotationPosition = [max(1, annotationPosition(1, :)); min(TileSize([2 1]), annotationPosition(2, :))];
            
            subMask = regionMask(annotationRegion(1, 1):annotationRegion(2, 1), annotationRegion(1, 2):annotationRegion(2, 2));
  
            if nnz(subMask) > 0
                if isfile(maskPath)
                    mask = im2double(imread(maskPath));
                else
                    if currentTileSize(2)~=TileSize(2) || currentTileSize(1)~=TileSize(1)
                        disp(['error for  tile size ',maskPath])
                    else
                    currentTileSize = min(TileSize([2 1]), ImageSize([2 1])-([v u].*TileSize([2 1])));
                    mask = zeros(currentTileSize);
                    end
                end

                mask(annotationPosition(1, 1):annotationPosition(2, 1), annotationPosition(1, 2):annotationPosition(2, 2)) = max(mask(annotationPosition(1, 1):annotationPosition(2, 1), annotationPosition(1, 2):annotationPosition(2, 2)), subMask);
                % to do initial test
%                 figure;
%                 BW = imbinarize(mask);
%                 [Bpred,~] = bwboundaries(BW,'noholes');
%                 imshow(tile10x)
%                 hold on
%                 for k = 1:length(Bpred)
%                     boundary = Bpred{k};
%                     plot(boundary(:,2), boundary(:,1), 'b', 'LineWidth', 1)
%                 end
                imwrite(mask, maskPath);
                % Bilinear interpolation; the output pixel value is a weighted average of pixels in the nearest 2-by-2 neighborhood
                imwrite(imresize(mask,.5,'bilinear'), strrep(maskPath,'10x','1x'));%
                imwrite(imresize(mask,2,'bilinear'), strrep(maskPath,'10x','20x'));
%                 imwrite(imresize(mask,4,'bilinear'), strrep(maskPath,'10x','40x'));
%             end
        end
    end
    %end
end
end

