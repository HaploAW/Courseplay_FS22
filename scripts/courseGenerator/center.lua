--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--- Functions to generate the up/down tracks in the center
--  of the field (non-headland tracks)

local rotatedMarks = {}

-- Up/down mode is a regular up/down pattern, may skip rows between for wider turns

CourseGenerator.CENTER_MODE_UP_DOWN = 1

-- Spiral mode: the center is split into multiple blocks, one block
-- is not more than 10 rows wide. Each block is then worked in a spiral
-- fashion from the outside to the inside, see below:

--  ----- 1 ---- < -------  \
--  ----- 3 ---- < -------  |
--  ----- 5 ---- < -------  |
--  ----- 6 ---- > -------  | Block 1
--  ----- 4 ---- > -------  |
--  ----- 2 ---- > -------  /
--  ----- 7 ---- < -------  \
--  ----- 9 ---- < -------  |
--  -----11 ---- < -------  | Block 2
--  -----12 ---- > -------  |
--  -----10 ---- > -------  |
--  ----- 8 ---- > -------  /
CourseGenerator.CENTER_MODE_SPIRAL = 2

-- Circular mode, (for now) the area is split into multiple blocks which are then worked one by one. Work in each
-- block starts around the middle, skipping a maximum of four rows to avoid 180 turns and working the block in
-- a circular, racetrack like pattern.
-- Depending on the number of rows, there may be a few of them left at the end which will need to be worked in a
-- regular up/down pattern
--  ----- 2 ---- > -------     \
--  ----- 4 ---- > -------     |
--  ----- 6 ---- > -------     |
--  ----- 8 ---- > -------     | Block 1
--  ----- 1 ---- < -------     |
--  ----- 3 ---- < -------     |
--  ----- 5 ---- < ------      |
--  ----- 7 ---- < -------     /
--  -----10 ---- > -------    \
--  -----12 ---- > -------     |
--  ----- 9 ---- < -------     | Block 2
--  -----11 ---- < -------     /
CourseGenerator.CENTER_MODE_CIRCULAR = 3

-- Lands mode, making a break through the field and progressively working
-- outwards in a counterclockwise spiral fashion
--  ----- 5 ---- < -------  \
--  ----- 3 ---- < -------  |
--  ----- 1 ---- < -------  |
--  ----- 2 ---- > -------  | Block 1
--  ----- 4 ---- > -------  |
--  ----- 6 ---- > -------  /
--  -----11 ---- < -------  \
--  ----- 9 ---- < -------  |
--  ----- 7 ---- < -------  | Block 2
--  ----- 8 ---- > -------  |
--  -----10 ---- > -------  |
--  -----12 ---- > -------  /
CourseGenerator.CENTER_MODE_LANDS = 4

CourseGenerator.centerModeTexts = {'up/down', 'spiral', 'circular', 'lands'}
CourseGenerator.CENTER_MODE_MIN = CourseGenerator.CENTER_MODE_UP_DOWN
CourseGenerator.CENTER_MODE_MAX = CourseGenerator.CENTER_MODE_LANDS

-- Distance of waypoints on the generated track in meters
CourseGenerator.waypointDistance = 5
-- don't generate waypoints closer than minWaypointDistance 
local minWaypointDistance = CourseGenerator.waypointDistance * 0.25
-- When splitting a field into blocks (due to islands or non-convexity) 
-- consider a block 'small' if it has less than smallBlockTrackCountLimit tracks. 
-- These are not prefered and will get a penalty in the scoring
local smallBlockTrackCountLimit = 5

-- 3D table returning the exit corner
-- first dimension is the entry corner
-- second dimension is a boolean: if true, the exit is on the same side (left/right)
-- third dimension is a boolean: if true, the exit is on the same edge (top/bottom)
local exitCornerMap = {
	[CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT] = {
		[true] = { [true] = CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT, [false] = CourseGenerator.BLOCK_CORNER_TOP_LEFT },
		[false] = {[true] = CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT,[false] = CourseGenerator.BLOCK_CORNER_TOP_RIGHT}
	},
	[CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT] = {
		[true] = { [true] = CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT,[false] = CourseGenerator.BLOCK_CORNER_TOP_RIGHT },
		[false] = {[true] = CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT, [false] = CourseGenerator.BLOCK_CORNER_TOP_LEFT}
	},
	[CourseGenerator.BLOCK_CORNER_TOP_LEFT] = {
		[true] = { [true] = CourseGenerator.BLOCK_CORNER_TOP_LEFT,    [false] = CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT },
		[false] = {[true] = CourseGenerator.BLOCK_CORNER_TOP_RIGHT,   [false] = CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT}
	},
	[CourseGenerator.BLOCK_CORNER_TOP_RIGHT] = {
		[true] = { [true] = CourseGenerator.BLOCK_CORNER_TOP_RIGHT,   [false] = CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT },
		[false] = {[true] = CourseGenerator.BLOCK_CORNER_TOP_LEFT,    [false] = CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT}
	},
}

--- find the corner where we will exit the block if entering at entry corner.
local function getBlockExitCorner( entryCorner, nRows, nRowsToSkip )
	-- if we have an even number of rows, we'll end up on the same side (left/right)
	local sameSide = nRows % 2 == 0
	-- if we skip an odd number of rows, we'll end up where we started (bottom/top)
	local sameEdge = nRowsToSkip % 2 == 1
	return exitCornerMap[ entryCorner ][ sameSide ][ sameEdge ]
end


local function isCornerOnTheBottom( entryCorner )
	return entryCorner == CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT or entryCorner == CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT
end

local function isCornerOnTheLeft( entryCorner )
	return entryCorner == CourseGenerator.BLOCK_CORNER_TOP_LEFT or entryCorner == CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT
end

--- Count the blocks with just a few tracks
local function countSmallBlockScore( blocks )
	local nResult = 0
	-- if there's only one block, we don't care
	if #blocks == 1 then return nResult end
	for _, b in ipairs( blocks ) do
		-- TODO: consider implement width
		if #b < smallBlockTrackCountLimit then
			nResult = nResult + smallBlockTrackCountLimit - #b
			--nResult = nResult + 1
		end
	end
	return nResult
end

--- Find the best angle to use for the tracks in a polygon.
--  The best angle results in the minimum number of tracks
--  (and thus, turns) needed to cover the polygon.
function CourseGenerator.findBestTrackAngle( polygon, islands, width, distanceFromBoundary, centerSettings )
	local bestAngleStats = {}
	local bestAngleIndex
	local score
	local minScore = 10000
	polygon:calculateData()

	-- direction where the field is the longest
	local bestDirection = polygon.bestDirection.dir
	local minAngleDeg, maxAngleDeg, step

	if centerSettings.useLongestEdgeAngle then
		-- use the direction of the longest edge of the polygon
		minAngleDeg, maxAngleDeg, step = - bestDirection, - bestDirection, 1
		CourseGenerator.debug( 'ROW ANGLE: USING THE LONGEST FIELD EDGE ANGLE OF %.0f', bestDirection )
	elseif centerSettings.useBestAngle then
		-- find the optimum angle
		minAngleDeg, maxAngleDeg, step = 0, 180, 2
		CourseGenerator.debug( 'ROW ANGLE: FINDING THE OPTIMUM ANGLE' )
	else
		-- use the supplied angle
		minAngleDeg, maxAngleDeg, step = math.deg( centerSettings.rowAngle ), math.deg( centerSettings.rowAngle ), 1
		CourseGenerator.debug( 'ROW ANGLE: USING THE SUPPLIED ANGLE OF %.0f', CourseGenerator.getCompassAngleDeg( math.deg( centerSettings.rowAngle )))
	end
	for angle = minAngleDeg, maxAngleDeg, step do
		local rotated = rotatePoints( polygon, math.rad( angle ))

		local rotatedIslands = Island.rotateAll( islands, math.rad( angle ))

		local tracks = CourseGenerator.generateParallelTracks( rotated, rotatedIslands, width, distanceFromBoundary )
		local blocks = splitCenterIntoBlocks( tracks, width )
		local smallBlockScore = countSmallBlockScore( blocks )
		-- instead of just the number of tracks, consider some other factors. We prefer just one block (that is,
		-- the field has a convex solution) and angles closest to the direction of the longest edge of the field
		-- sin( angle - BestDir ) will be 0 when angle is the closest.
		local angleScore = bestDirection and
			3 * math.abs( math.sin( getDeltaAngle( math.rad( angle ), math.rad( bestDirection )))) or 0
		score = 50 * smallBlockScore + 10 * #blocks + #tracks + angleScore
		-- CourseGenerator.debug( "Tried angle=%d, nBlocks=%d, smallBlockScore=%d, tracks=%d, score=%.1f",
		--	angle, #blocks, smallBlockScore, #tracks, score)
		table.insert( bestAngleStats, { angle=angle, nBlocks=#blocks, nTracks=#tracks, score=score, smallBlockScore=smallBlockScore })
		if minScore > score then
			minScore = score
			bestAngleIndex = #bestAngleStats
		end
	end
	local b = bestAngleStats[ bestAngleIndex ]
	CourseGenerator.debug( "Best angle=%d, nBlocks=%d, nTracks=%d, smallBlockScore=%d, score=%.1f",
		b.angle, b.nBlocks, b.nTracks, b.smallBlockScore, b.score)
	-- if we used the angle given by the user and got small blocks generated,
	-- we might want to warn them that the course may be less than perfect.
	return b.angle, b.nTracks, b.nBlocks
end

local function addWaypointsToBlocks(blocks, width, nHeadlandPasses)
	-- using a while loop as we'll remove blocks if they have no tracks
	local nTotalTracks = 0
	local i = 1
	while blocks[i] do
		local block = blocks[i]
		nTotalTracks = nTotalTracks + #block
		CourseGenerator.debug( "Block %d has %d tracks", i, #block )
		block.tracksWithWaypoints = addWaypointsToTracks( block, width, nHeadlandPasses )
		block.covered = false
		-- we may end up with blocks without tracks in case we did not find a single track
		-- with at least two waypoints. Now remove those blocks
		if #blocks[i].tracksWithWaypoints == 0 then
			CourseGenerator.debug( "Block %d removed as it has no tracks with waypoints", i)
			table.remove(blocks, i)
		else
			i = i + 1
		end
	end
	return nTotalTracks
end

local function reverseTracks( tracks )
	local reversedTracks = {}
	for i = #tracks, 1, -1 do
		table.insert( reversedTracks, tracks[ i ])
	end
	return reversedTracks
end

--- Link the parallel tracks in the center of the field to one
-- continuous track.
-- if bottomToTop == true then start at the bottom and work our way up
-- if leftToRight == true then start the first track on the left
-- centerSettings - all center related settings
-- tracks
local function linkParallelTracks(parallelTracks, bottomToTop, leftToRight, centerSettings, startWithTurn)
	if not bottomToTop then
		-- we start at the top, so reverse order of tracks as after the generation,
		-- the last one is on the top
		parallelTracks = reverseTracks( parallelTracks )
	end
	local start
	if centerSettings.mode == CourseGenerator.CENTER_MODE_UP_DOWN then
		parallelTracks = reorderTracksForAlternateFieldwork(parallelTracks, centerSettings.nRowsToSkip,
			centerSettings.leaveSkippedRowsUnworked)
		start = leftToRight and 2 or 1
	elseif centerSettings.mode == CourseGenerator.CENTER_MODE_SPIRAL then
		parallelTracks = reorderTracksForSpiralFieldwork(parallelTracks)
		start = leftToRight and 2 or 1
	elseif centerSettings.mode == CourseGenerator.CENTER_MODE_CIRCULAR then
		parallelTracks = reorderTracksForCircularFieldwork(parallelTracks)
		start = leftToRight and 2 or 1
	elseif centerSettings.mode == CourseGenerator.CENTER_MODE_LANDS then
		parallelTracks = reorderTracksForLandsFieldwork(parallelTracks, leftToRight, bottomToTop,
			centerSettings.nRowsPerLand, centerSettings.pipeOnLeftSide)
		start = leftToRight and 2 or 1
	end
	-- now make sure that the we work on the tracks in alternating directions
	-- we generate track from left to right, so the ones which we'll traverse
	-- in the other direction must be reversed.
	-- reverse every second track
	for i = start, #parallelTracks, 2 do
		parallelTracks[ i ].waypoints = reverse( parallelTracks[ i ].waypoints)
	end
	local result = Polyline:new()
	local startTrack = 1
	local endTrack = #parallelTracks
	for i = startTrack, endTrack do
		if parallelTracks[ i ].waypoints then
			for j, point in ipairs(parallelTracks[ i ].waypoints) do
				-- the first point of a track is the end of the turn (except for the first track)
				if ( j == 1 and ( i ~= startTrack or startWithTurn )) then
					point.turnEnd = true
				end
				-- these will come in handy for the ridge markers
				point.rowNumber = i
				point.originalRowNumber = parallelTracks[ i ].originalRowNumber
				point.adjacentIslands = parallelTracks[ i ].adjacentIslands
				point.lastTrack = i == endTrack
				point.firstTrack = i == startTrack
				-- the last point of a track is the start of the turn (except for the last track)
				if ( j == #parallelTracks[ i ].waypoints and i ~= endTrack ) then
					point.turnStart = true
					table.insert( result, point )
				else
					table.insert( result, point )
				end
			end
		else
			CourseGenerator.debug( "Track %d has no waypoints, skipping.", i )
		end
	end
	return result
end

--- Generate up/down rows covering a polygon at the optimum angle
---@return table[], number, number, table[], boolean course, bestAngle, #parallelTracks, blocks,
--- resultIsOk if false, no usable course is generated
function CourseGenerator.generateFieldCenter( headlands, islands, width, headlandSettings, centerSettings )

	local nHeadlandPasses = (headlandSettings.mode == CourseGenerator.HEADLAND_MODE_NORMAL or
		headlandSettings.mode == CourseGenerator.HEADLAND_MODE_NARROW_FIELD) and headlandSettings.nPasses or 0
	local distanceFromBoundary
	if nHeadlandPasses == 0 then
		distanceFromBoundary = width / 2
	else
		distanceFromBoundary = width
	end

	-- get the innermost headland
	local innermostHeadland = headlands[#headlands]
	-- translate headlands so we can rotate them around their center. This way all points
	-- will be approximately the same distance from the origin and the rotation calculation
	-- will be more accurate. This will the boundary of the field center where the parallel rows are running
	local boundary = Polygon:copy(innermostHeadland)
	local dx, dy = boundary:getCenter()
	-- boundary transformed in the field centered coordinate system. First, just translate, will rotate once
	-- we figure out the angle
	boundary:translate(-dx, -dy)

	local translatedIslands = Island.translateAll( islands, -dx, -dy )

	local bestAngle, nTracks, nBlocks
	-- Now, determine the angle where the number of tracks is the minimum
	bestAngle, nTracks, nBlocks = CourseGenerator.findBestTrackAngle(boundary, translatedIslands, width, distanceFromBoundary, centerSettings)
	if nBlocks < 1 then
		CourseGenerator.debug( "No room for up/down rows." )
		return nil, 0, 0, nil, true
	end
	if not bestAngle then
		bestAngle = headlands[#headlands].bestDirection.dir
		CourseGenerator.debug( "No best angle found, use the longest edge direction " .. bestAngle )
	end
	rotatedMarks = Polygon:new()
	-- now, generate the tracks according to the implement width within the rotated boundary's bounding box
	-- using the best angle
	-- rotate everything we'll need later
	boundary:rotate(math.rad(bestAngle))
	local rotatedIslands = Island.rotateAll( translatedIslands, math.rad( bestAngle ))

	-- if we have headlands, let all rows have the same width, the last one overlapping with the headland
	local parallelTracks, offset = CourseGenerator.generateParallelTracks(boundary, rotatedIslands, width, distanceFromBoundary, nHeadlandPasses > 0)

	local blocks = splitCenterIntoBlocks( parallelTracks, width )

	local nTotalTracks = addWaypointsToBlocks(blocks, width, nHeadlandPasses)

	if #blocks > 30 or ( #blocks > 1 and ( nTotalTracks / #blocks ) < 2 ) then
		-- don't waste time on unrealistic problems
		CourseGenerator.debug( 'Implausible number of blocks/tracks (%d/%d), not generating up/down rows', #blocks, nTotalTracks )
		return nil, 0, 0, nil, false
	end

	-- We now have split the area within the headland into blocks. If this is
	-- a convex polygon, there is only one block, non-convex ones may have multiple
	-- blocks.
	-- Now we have to connect the first block with the end of the headland track
	-- and then connect each block so we cover the entire polygon.
	math.randomseed( CourseGenerator.getCurrentTime())
	local blocksInSequence = findBlockSequence( blocks, boundary, innermostHeadland.circleStart, innermostHeadland.circleStep, nHeadlandPasses, centerSettings.nRowsToSkip)
	local workedBlocks = linkBlocks( blocksInSequence, boundary, innermostHeadland.circleStart, innermostHeadland.circleStep, centerSettings.nRowsToSkip)

	-- workedBlocks has now a the list of blocks we need to work on, including the track
	-- leading to the block from the previous block or the headland.
	local track = Polygon:new()
	local connectingTracks = {} -- only for visualization/debug
	for i, block in ipairs( workedBlocks ) do
		connectingTracks[ i ] = Polygon:new()
		local nPoints = block.trackToThisBlock and #block.trackToThisBlock or 0
		CourseGenerator.debug( "Connecting track to block %d has %d points", i, nPoints )
		-- do not add connecting tracks to the first block (or if there's no headland)
		if nHeadlandPasses > 0 and i > 1 then
			for j = 1, nPoints do
				table.insert( connectingTracks[ i ], block.trackToThisBlock[ j ])
				table.insert( track, block.trackToThisBlock[ j ])
				-- mark this section as a connecting track where implements should be raised as we are
				-- driving on a previously worked headland track.
				track[ #track ].isConnectingTrack = true
			end
		end
		CourseGenerator.debug( '%d. block %d, entry corner %d, direction to next = %d, on the bottom = %s, on the left = %s', i, block.id, block.entryCorner,
				block.directionToNextBlock or 0, tostring( isCornerOnTheBottom( block.entryCorner )), tostring( isCornerOnTheLeft( block.entryCorner )))
		local continueWithTurn = not block.trackToThisBlock
		if continueWithTurn then
			track[ #track ].turnStart = true
		end
		local linkedTracks = linkParallelTracks(block.tracksWithWaypoints,
				isCornerOnTheBottom( block.entryCorner ), isCornerOnTheLeft( block.entryCorner ), centerSettings, continueWithTurn)
		-- remember where the up/down rows start (transition from headland to up/down rows)
		if i == 1 then
			linkedTracks[1].upDownRowStart = #track
		end
		for _, p in ipairs(linkedTracks) do
			table.insert(track, p)
		end
	end

	if centerSettings.nRowsToSkip == 0 then
		-- do not add ridge markers if we are skipping rows, don't need when working with GPS :)
		addRidgeMarkers( track )
	end
	-- now rotate and translate everything back to the original coordinate system
	if marks then
		rotatedMarks = translatePoints( rotatePoints( rotatedMarks, -math.rad( bestAngle )), dx, dy )
		for i = 1, #rotatedMarks do
			table.insert( marks, rotatedMarks[ i ])
		end
	end
	for i = 1, #connectingTracks do
		connectingTracks[ i ] = translatePoints( rotatePoints( connectingTracks[ i ], -math.rad( bestAngle )), dx, dy )
	end
	boundary.connectingTracks = connectingTracks
	-- return the information about blocks for visualization
	for _, b in ipairs( blocks ) do
		b.polygon:rotate( -math.rad( bestAngle ))
		b.polygon:translate( dx, dy )
	end
	return translatePoints( rotatePoints( track, -math.rad( bestAngle )), dx, dy ), bestAngle, #parallelTracks, blocks, true
end

----------------------------------------------------------------------------------
-- Functions below work on a field rotated so that all parallel tracks are 
-- horizontal ( y = constant ). This makes track calculation really easy.
----------------------------------------------------------------------------------

--- Generate a list of parallel tracks within the field's boundary
-- At this point, tracks are defined only by they endpoints and 
-- are not connected
---@param useSameWidth boolean if true, the distance between all rows is the same, otherwise, the last
--- row is narrower so it does not overlap with the headland or the area around the field
---@return table[], number rows and the offset. The last row we generate (which is on the top) will always
--- overlap either the previous row or the headland (if useSameWidth true). At this point however, we don't know
--- if the last generated row will also be the last worked on, depending on many factors, especially if there are
--- multiple blocks, the rows may be worked on in the opposite order. However, we always want the last row to
--- overlap, so if it turns out later that the rows are worked in the opposite order, we'll just need to shift
--- all rows down by offset meters.
function CourseGenerator.generateParallelTracks(polygon, islands, width, distanceFromBoundary, useSameWidth)
	local tracks = {}
	local offset
	local function addTrack( fromX, toX, y, ix )
		local from = { x = fromX, y = y, track=ix }
		local to = { x = toX, y = y, track=ix }
		-- for now, all tracks go from min to max, we'll take care of
		-- alternating directions later.
		table.insert( tracks, { from=from, to=to, intersections={}, originalRowNumber = ix } )
	end
	local trackIndex = 1
	local y = polygon.boundingBox.minY + distanceFromBoundary
	while y < polygon.boundingBox.maxY - distanceFromBoundary do
		addTrack( polygon.boundingBox.minX, polygon.boundingBox.maxX, y, trackIndex )
		trackIndex = trackIndex + 1
		y = y + width
	end
	-- add the last track
	addTrack(polygon.boundingBox.minX, polygon.boundingBox.maxX, y, trackIndex)
	if useSameWidth then
		offset = distanceFromBoundary - (polygon.boundingBox.maxY - tracks[#tracks].from.y)
	else
		-- pull the last row in so it does not extend over the field center
		tracks[#tracks].from.y = polygon.boundingBox.maxY - distanceFromBoundary
		tracks[#tracks].to.y = polygon.boundingBox.maxY - distanceFromBoundary
	end
	if #tracks > 1 and  math.abs(tracks[#tracks].from.y - tracks[#tracks - 1].from.y) < 0.1 then
		-- so there are no complaints that vehicles drive an extra row, and hopefully, with less than 10 cm left,
		-- there will be no unworked area
		CourseGenerator.debug('Last two rows too close, removing one')
		table.remove(tracks)
	end
	-- tracks has now a list of segments covering the bounding box of the
	-- field.
	findIntersections( polygon, tracks )
	for _, island in ipairs( islands ) do
		if #island.headlandTracks > 0 then
			findIntersections( island.headlandTracks[ island.outermostHeadlandIx ], tracks, island.id )
		end
	end
	return tracks, offset
end

--- Input is a field boundary (like the innermost headland track or a
--  headland around an island) and 
--  a list of segments. The segments represent the up/down rows. 
--  This function finds the intersections with the the field
--  boundary.
--  As result, tracks will have an intersections member with all 
--  intersection points with the headland, ordered from left to right
function findIntersections( headland, tracks, islandId )
	-- recalculate angles after the rotation for getDistanceBetweenTrackAndHeadland()
	headland:calculateData()
	-- loop through the polygon and check each vector from
	-- the current point to the next
	for i, cp in headland:iterator() do
		local np = headland[ i + 1 ]
		for j, t in ipairs( tracks ) do
			local is = getIntersection( cp.x, cp.y, np.x, np.y, t.from.x, t.from.y, t.to.x, t.to.y )
			if is then
				-- the line between from and to (the track) intersects the vector from cp to np
				-- remember the angle we cross the headland
				is.angle = cp.tangent.angle
				is.islandId = islandId
				-- also remember which headland this was, we have one boundary around the entire
				-- field and one around each island.
				is.headland = headland
				-- remember where we intersect the headland.
				is.headlandEdge = {fromIx = i, toIx = i + 1}
				is.originalRowNumber = t.originalRowNumber
				t.onIsland = islandId
				addPointToListOrderedByX( t.intersections, is )
			end
		end
	end
	-- now that we know which tracks are on the island, detect tracks adjacent to an island
	if islandId then
		for i = 1, #tracks do
			local previousTrack = tracks[ i - 1 ]
			local t = tracks[ i ]
			--print( t.originalRowNumber, previousTrack and previousTrack.onIsland or nil, t.onIsland )
			if previousTrack and previousTrack.onIsland and not t.onIsland then
				if not t.adjacentIslands then t.adjacentIslands = {} end
				t.adjacentIslands[ islandId ] = true
			end
			if previousTrack and not previousTrack.onIsland and t.onIsland then
				if not previousTrack.adjacentIslands then previousTrack.adjacentIslands = {} end
				previousTrack.adjacentIslands[ islandId ] = true
			end
			previousTrack = t
		end
	end
end

--- Make sure angle is at least limit, to avoid division by near zero numbers
---@param angle number angle in radians
---@param limit number optional limit in radians, default 15 degrees
local function ensureNonZeroAngle(angle, limit)
	limit = limit or math.pi / 12
	if math.abs(angle) < limit then
		return limit
	else
		return angle
	end
end

-- how far to drive beyond the field edge/headland if we hit it at an angle, to cover the row completely
local function getDistanceToFullCover( width, angle )
	-- with very low angles this becomes too much, in that case you need a headland, so limit it here
	return math.abs( width / 2 / math.tan(ensureNonZeroAngle(angle)))
end

-- if the up/down tracks were perpendicular to the boundary, we'd have to cut them off
-- width/2 meters from the intersection point with the boundary. But if we drive on to the
-- boundary at an angle, we have to drive further if we don't want to miss fruit.
-- Note, this also works on unrotated polygons/tracks, all we need is to use the
-- angle difference between the up/down and headland tracks instead of just the angle
-- of the headland track
local function getDistanceBetweenRowEndAndHeadland(width, angle )
	angle = ensureNonZeroAngle(angle)
	-- distance between headland centerline and side at an angle
	-- (is width / 2 when angle is 90 degrees)
	local dHeadlandCenterAndSide = math.abs( width / 2 / math.sin( angle ))
	return dHeadlandCenterAndSide - getDistanceToFullCover(width, angle)
end

--- convert a list of tracks to waypoints, also cutting off
-- the part of the track which is outside of the field.
--
-- use the fact that at this point the field and the tracks
-- are rotated so that the tracks are parallel to the x axle and 
-- the first track has the lowest y coordinate
--
-- Also, we expect the tracks already have the intersection points with
-- the field boundary (or innermost headland) and there are exactly two intersection points
function addWaypointsToTracks( tracks, width, nHeadlandPasses )
	local result = {}
	for i = 1, #tracks do
		if #tracks[ i ].intersections > 1 then
			local isFromIx = tracks[ i ].intersections[ 1 ].x < tracks[ i ].intersections[ 2 ].x and 1 or 2
			-- if there are no headlands, tracks intersect with the field boundary, not the headland
			-- therefore, this offset (distance from the intersection to the point where the up/down row ends),
			-- is calculated differently in each case
			local offset
			if nHeadlandPasses == 0 then
				offset = -getDistanceToFullCover( width, tracks[ i ].intersections[ isFromIx ].angle )
			else
				offset = getDistanceBetweenRowEndAndHeadland( width, tracks[ i ].intersections[ isFromIx ].angle )
			end
			local newFrom = tracks[ i ].intersections[ isFromIx ].x + offset - width * 0.05  -- always overlap a bit with the headland to avoid missing fruit
			local isToIx = tracks[ i ].intersections[ 1 ].x >= tracks[ i ].intersections[ 2 ].x and 1 or 2
			if nHeadlandPasses == 0 then
				offset = -getDistanceToFullCover( width, tracks[ i ].intersections[ isToIx ].angle )
			else
				offset = getDistanceBetweenRowEndAndHeadland( width, tracks[ i ].intersections[ isToIx ].angle )
			end
			local newTo = tracks[ i ].intersections[ isToIx ].x - offset + width * 0.05  -- always overlap a bit with the headland to avoid missing fruit
			-- if a track is very short (shorter than width) we may end up with newTo being
			-- less than newFrom. Just skip that track
			if newTo > newFrom then
				tracks[ i ].waypoints = {}
				for x = newFrom, newTo, CourseGenerator.waypointDistance do
					table.insert( tracks[ i ].waypoints, { x=x, y=tracks[ i ].from.y, track=i })
				end
				-- make sure we actually reached newTo, if waypointDistance is too big we may end up
				-- well before the innermost headland track or field boundary, or even worse, with just
				-- a single waypoint
				if newTo - tracks[ i ].waypoints[ #tracks[ i ].waypoints ].x > minWaypointDistance then
					table.insert( tracks[ i ].waypoints, { x=newTo, y=tracks[ i ].from.y, track=i })
				end
			end
		end
		-- return only tracks with at least two waypoints
		if tracks[ i ].waypoints then
			if #tracks[ i ].waypoints > 1 then
				table.insert( result, tracks[ i ])
			else
				CourseGenerator.debug( "Track %d has only one waypoint, skipping.", i )
			end
		else
			CourseGenerator.debug('Track %d has no waypoints', i)
		end
	end
	CourseGenerator.debug('Generated %d tracks for this block', #result)
	return result
end

--- Check parallel tracks to see if the turn start and turn end waypoints
-- are too far away. If this is the case, add waypoints
-- Assume this is called at the first waypoint of a new track (turnEnd == true)
--
-- This may help the auto turn algorithm, sometimes it can't handle turns 
-- when turnstart and turnend are too far apart
--
function addWaypointsForTurnsWhenNeeded( track )
	local result = {}
	for i, point in ipairs( track ) do
		if point.turnEnd then
			local distanceFromTurnStart = getDistanceBetweenPoints( point, track[ i - 1 ])
			if distanceFromTurnStart > CourseGenerator.waypointDistance * 2 then
				-- too far, add a waypoint between the start of the current track and
				-- the end of the previous one.
				local x, y = getPointInTheMiddle( point, track[ i - 1])
				-- also, we are moving the turn end to this new point
				track[ i - 1 ].turnStart = nil
				table.insert( result, { x=x, y=y, turnStart=true })
			end
		end
		table.insert( result, point )
	end
	CourseGenerator.debug( "track had " .. #track .. ", result has " .. #result )
	return result
end

--- Reorder parallel tracks for alternating track fieldwork.
-- This allows for example for working on every odd track first 
-- and then on the even ones so turns at track ends can be wider.
--
-- For example, if we have five tracks: 1, 2, 3, 4, 5, and we 
-- want to skip every second track, we'd work in the following 
-- order: 1, 3, 5, 4, 2
--
function reorderTracksForAlternateFieldwork(parallelTracks, nRowsToSkip, leaveSkippedRowsUnworked)
	-- start with the first track and work up to the last,
	-- skipping every nTrackToSkip tracks.
	local reorderedTracks = {}
	local workedTracks = {}
	local lastWorkedTrack
	local done = false
	-- need to work on this until all tracks are covered
	while (#reorderedTracks < #parallelTracks) and not done do
		-- find first non-worked track
		local start = 1
		while workedTracks[ start ] do start = start + 1 end
		for i = start, #parallelTracks, nRowsToSkip + 1 do
			table.insert( reorderedTracks, parallelTracks[ i ])
			workedTracks[ i ] = true
			lastWorkedTrack = i
		end
		-- if we don't want to work on the skipped rows, we are done here
		if leaveSkippedRowsUnworked then
			done = true
		else
			-- now work on the skipped rows if that is desired
			-- we reached the last track, now turn back and work on the
			-- rest, find the last unworked track first
			for i = lastWorkedTrack + 1, 1, - ( nRowsToSkip + 1 ) do
				if ( i <= #parallelTracks ) and not workedTracks[ i ] then
					table.insert( reorderedTracks, parallelTracks[ i ])
					workedTracks[ i ] = true
				end
			end
		end
	end
	return reorderedTracks
end

--- See CourseGenerator.CENTER_MODE_SPIRAL for an explanation
function reorderTracksForSpiralFieldwork(parallelTracks)
	local reorderedTracks = {}
	for i = 1, math.floor(#parallelTracks / 2) do
		table.insert(reorderedTracks, parallelTracks[i])
		table.insert(reorderedTracks, parallelTracks[#parallelTracks - i + 1])
	end
	if #parallelTracks % 2 ~= 0 then
		table.insert(reorderedTracks, parallelTracks[math.ceil(#parallelTracks /2)])
	end
	return reorderedTracks
end

--- See CourseGenerator.CENTER_MODE_CIRCULAR for an explanation
function reorderTracksForCircularFieldwork(parallelTracks)
	local reorderedTracks = {}
	local SKIP_FWD = {} -- skipping rows towards the end of field
	local SKIP_BACK = {} -- skipping rows towards the beginning of the field
	local FILL_IN = {} -- filling in whatever is left after skipping
	local n = #parallelTracks
	local nSkip = 4
	local rowsDone = {}
	-- start in the middle
	local i = nSkip + 1
	table.insert(reorderedTracks, parallelTracks[i])
	rowsDone[i] = true
	local nDone = 1
	local mode = SKIP_BACK
	-- start circling
	while nDone < n do
		local nextI
		if mode == SKIP_FWD then
			nextI = i + nSkip + 1
			mode = SKIP_BACK
		elseif mode == SKIP_BACK then
			nextI = i - nSkip
			mode = SKIP_FWD
		elseif mode == FILL_IN then
			nextI = i + 1
		end
		if rowsDone[nextI] then
			-- this has been done already, so skip forward to the next block
			nextI = i + nSkip + 1
			mode = SKIP_BACK
		end
		if nextI > n then
			-- reached the end of the field with the current skip, start skipping less, but keep skipping rows
			-- as long as we can to prevent backing up in turn maneuvers
			nSkip = math.floor((n - nDone) / 2)
			if nSkip > 0 then
				nextI = i + nSkip + 1
				mode = SKIP_BACK
			else
				-- no room to skip anymore
				mode = FILL_IN
				nextI = i + 1
			end
		end
		i = nextI
		rowsDone[i] = true
		table.insert(reorderedTracks, parallelTracks[i])
		nDone = nDone + 1
	end
	return reorderedTracks
end

-- Work the tracks in a sequence that makes sure the pipe is not in the fruit
function reorderTracksForLandsFieldwork(parallelTracks, leftToRight, bottomToTop, nRowsInLands, pipeOnLeftSide)
	local reorderedTracks = {}
	-- For pipe on the left side (most combines) we drive in a counterclockwise outward spiral the pipe
	-- pointing to the inside, harvested land
	local counterclockwise = (leftToRight and bottomToTop) or (not leftToRight and not bottomToTop)
	if not pipeOnLeftSide then
		CourseGenerator.debug( "Pipe is on the right side, flip direction for lands mode")
		-- Flip for pipe on the right side (some potato harvesters) and drive in a clockwise direction to make
		-- sure the pipe points again to the inside, harvested land
		counterclockwise = not counterclockwise
	end
	-- I know this could be generated but it is more readable and easy to visualize this way.
	local rowOrderInLands = counterclockwise and
			{
				{1},
				{2, 1},
				{2, 3, 1},
				{2, 3, 1, 4},
				{3, 4, 2, 5, 1},
				{3, 4, 2, 5, 1, 6},
				{4, 5, 3, 6, 2, 7, 1},
				{4, 5, 3, 6, 2, 7, 1, 8},
				{5, 6, 4, 7, 3, 8, 2, 9, 1},
				{5, 6, 4, 7, 3, 8, 2, 9, 1, 10},
				{6, 7, 5, 8, 4, 9, 3, 10, 2, 11, 1},
				{6, 7, 5, 8, 4, 9, 3, 10, 2, 11, 1, 12},
				{7, 8, 6, 9, 5, 10, 4, 11, 3, 12, 2, 13, 1},
				{7, 8, 6, 9, 5, 10, 4, 11, 3, 12, 2, 13, 1, 14},
				{8, 9, 7, 10, 6, 11, 5, 12, 4, 13, 3, 14, 2, 15, 1},
				{8, 9, 7, 10, 6, 11, 5, 12, 4, 13, 3, 14, 2, 15, 1, 16},
				{9, 10, 8, 11, 7, 12, 6, 13, 5, 14, 4, 15, 3, 16, 2, 17, 1},
				{9, 10, 8, 11, 7, 12, 6, 13, 5, 14, 4, 15, 3, 16, 2, 17, 1, 18},
				{10, 11, 9, 12, 8, 13, 7, 14, 6, 15, 5, 16, 4, 17, 3 , 18, 2, 19, 1},
				{10, 11, 9, 12, 8, 13, 7, 14, 6, 15, 5, 16, 4, 17, 3 , 18, 2, 19, 1, 20},
				{11, 12, 10, 13, 9, 14, 8, 15, 7, 16, 6, 17, 5, 18, 4, 19, 3, 20, 2, 21, 1},
				{11, 12, 10, 13, 9, 14, 8, 15, 7, 16, 6, 17, 5, 18, 4, 19, 3, 20, 2, 21, 1, 22},
				{12, 13, 11, 14, 10, 15, 9, 16, 8, 17, 7, 18, 6, 19, 5, 20, 4, 21, 3, 22, 2, 23, 1},
				{12, 13, 11, 14, 10, 15, 9, 16, 8, 17, 7, 18, 6, 19, 5, 20, 4, 21, 3, 22, 2, 23, 1, 24}
			} or
			{
				{1},
				{1, 2},
				{2, 1, 3},
				{3, 2, 4, 1},
				{3, 2, 4, 1, 5},
				{4, 3, 5, 2, 6, 1},
				{4, 3, 5, 2, 6, 1, 7},
				{5, 4, 6, 3, 7, 2, 8, 1},
				{5, 4, 6, 3, 7, 2, 8, 1, 9},
				{6, 5, 7, 4, 8, 3, 9, 2, 10, 1},
				{6, 5, 7, 4, 8, 3, 9, 2, 10, 1, 11},
				{7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1},
				{7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1, 13},
				{8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1},
				{8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15},
				{9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16, 1},
				{9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16, 1, 17},
				{10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1},
				{10, 9, 11, 8, 12, 7, 13, 6, 14, 5, 15, 4, 16, 3, 17, 2, 18, 1, 19},
				{11, 10, 12, 9, 13, 8, 14, 7, 15, 6, 16, 5, 17, 4, 18, 3, 19, 2, 20, 1},
				{11, 10, 12, 9, 13, 8, 14, 7, 15, 6, 16, 5, 17, 4, 18, 3, 19, 2, 20, 1, 21},
				{12, 11, 13, 10, 14, 9, 15, 8, 16, 7, 17, 6, 18, 5, 19, 4, 20, 3, 21, 2, 22, 1},
				{12, 11, 13, 10, 14, 9, 15, 8, 16, 7, 17, 6, 18, 5, 19, 4, 20, 3, 21, 2, 22, 1, 23},
				{13, 12, 14, 11, 15, 10, 16, 9, 17, 8, 18, 7, 19, 6, 20, 5, 21, 4, 22, 3, 23, 2, 24, 1}
			}

	for i = 0, math.floor(#parallelTracks / nRowsInLands) - 1 do
		for _, j in ipairs(rowOrderInLands[nRowsInLands]) do
			table.insert(reorderedTracks, parallelTracks[i * nRowsInLands + j])
		end
	end

	local lastRow = nRowsInLands * math.floor(#parallelTracks / nRowsInLands)
	local nRowsLeft = #parallelTracks % nRowsInLands

	if nRowsLeft > 0 then
		for _, j in ipairs(rowOrderInLands[nRowsLeft]) do
			table.insert(reorderedTracks, parallelTracks[lastRow + j])
		end
	end

	return reorderedTracks
end


--- Find blocks of center tracks which have to be worked separately
-- in case of non-convex fields or islands
--
-- These blocks consist of tracks and each of these tracks will have
-- exactly two intersection points with the headland
--
function splitCenterIntoBlocks( tracks, width )

	local function createEmptyBlocks( n )
		local b = {}
		for i = 1, n do
			table.insert( b, {})
		end
		return b
	end

	--- We may end up with a bogus block if the island headland intersects the field 
	-- headland. This bogus block will be between the outermost island headland and the
	-- innermost field headland. Try to remove those intersection points.
	-- most likely can happen with a field headland only on non-convex fields but not sure
	-- how to handle that case.
	local function cleanupIntersections( is )
		local onIsland = false
		for i = 2, #is do
			if not onIsland and is[ i - 1 ].islandId then
				is[ i - 1 ].deleteThis = true
				is[ i ].deleteThis = true
				onIsland = true
			elseif not onIsland and not is[ i - 1 ].islandId and is[ i ].islandId then
				onIsland = true
			elseif onIsland and not is[ i ].islandId then
				onIsland = false
			end
		end
		for i = #is, 1, -1 do
			if is[ i ].deleteThis then
				table.remove( is, i )
			end
		end
	end

	local function splitTrack( t )
		local splitTracks = {}
		cleanupIntersections( t.intersections )
		if #t.intersections % 2 ~= 0 or #t.intersections < 2 then
			CourseGenerator.debug( 'Found track with odd number (%d) of intersections', #t.intersections )
			table.remove( t.intersections, #t.intersections )
		end
		if t.to.x - t.from.x < 15 then
			CourseGenerator.debug( 'Found very short track %.1f m', t.to.x - t.from.x )
		end
		for i = 1, #t.intersections, 2 do
			local track = { from=t.from, to=t.to,
			                intersections={ shallowCopy( t.intersections[ i ]), shallowCopy( t.intersections[ i + 1 ])},
			                originalRowNumber = t.originalRowNumber,
			                adjacentIslands = t.adjacentIslands }
			table.insert( splitTracks, track )
		end
		return splitTracks
	end

	local function closeCurrentBlocks( blocks, currentBlocks )
		if currentBlocks then
			for _, block in ipairs( currentBlocks ) do
				-- for our convenience, remember the corners
				block.bottomLeftIntersection = block[ 1 ].intersections[ 1 ]
				block.bottomRightIntersection = block[ 1 ].intersections[ 2 ]
				block.topLeftIntersection = block[ #block ].intersections[ 1 ]
				block.topRightIntersection = block[ #block ].intersections[ 2 ]

				-- this is for visualization only
				block.polygon = Polygon:new()

				block.bottomLeftIntersection.label = CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT .. '(' .. block.bottomLeftIntersection.headlandEdge.fromIx .. ')'
				block.polygon[ CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT ] = block.bottomLeftIntersection
				table.insert( rotatedMarks, block.bottomLeftIntersection )

				block.bottomRightIntersection.label = CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT.. '(' .. block.bottomRightIntersection.headlandEdge.fromIx .. ')'
				block.polygon[ CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT ] = block.bottomRightIntersection
				table.insert( rotatedMarks, block.bottomRightIntersection )

				block.topRightIntersection.label = CourseGenerator.BLOCK_CORNER_TOP_RIGHT.. '(' .. block.topRightIntersection.headlandEdge.fromIx .. ')'
				block.polygon[ CourseGenerator.BLOCK_CORNER_TOP_RIGHT ] = block.topRightIntersection
				table.insert( rotatedMarks, block.topRightIntersection )

				block.topLeftIntersection.label = CourseGenerator.BLOCK_CORNER_TOP_LEFT .. '(' .. block.topLeftIntersection.headlandEdge.fromIx .. ')'
				block.polygon[ CourseGenerator.BLOCK_CORNER_TOP_LEFT ] = block.topLeftIntersection
				table.insert( rotatedMarks, block.topLeftIntersection )

				table.insert( blocks, block )
				block.id = #blocks
			end
		end
	end

	local blocks = {}
	local previousNumberOfIntersections = 0
	local currentNumberOfSections = 0
	local currentBlocks
	for i, t in ipairs( tracks ) do
		local startNewBlock = false
		local splitTracks = splitTrack( t )
		for j, s in ipairs( splitTracks ) do
			if currentBlocks and #currentBlocks == #splitTracks and
				#t.intersections == previousNumberOfIntersections and
				not overlaps( currentBlocks[ j ][ #currentBlocks[ j ]], s ) then
				--print( string.format( '%d. overlap currentBlocks = %d, splitTracks = %d', j, currentBlocks and #currentBlocks or 0, #splitTracks ))
				startNewBlock = true
			end
		end
		-- number of track sections after splitting this track. Will be exactly one
		-- if there are no obstacles in the field.
		currentNumberOfSections = math.floor( #t.intersections / 2 )

		if #t.intersections ~= previousNumberOfIntersections or startNewBlock then
			-- start a new block, first save the current ones if exist
			previousNumberOfIntersections = #t.intersections
			closeCurrentBlocks( blocks, currentBlocks )
			currentBlocks = createEmptyBlocks( currentNumberOfSections )
		end
		--print( i, #blocks, #currentBlocks, #splitTracks, currentNumberOfSections )
		for j, s in ipairs( splitTracks ) do
			table.insert( currentBlocks[ j ], s )
		end
	end
	closeCurrentBlocks( blocks, currentBlocks )
	return blocks
end

--- add a point to a list of intersections but make sure the 
-- list is ordered from left to right, that is, the first element has 
-- the smallest x, the last the greatest x
function addPointToListOrderedByX( is, point )
	local i = #is
	while i > 0 and point.x < is[ i ].x do
		i = i - 1
	end
	-- don't enter duplicates as that'll result in grid points outside the
	-- field (when used for the pathfinding)
	if i == 0 or point.x ~= is[ i ].x then
		table.insert( is, i + 1, point )
	end
end

--- check if two tracks overlap. We assume tracks are horizontal
-- and therefore check only the x coordinate
-- also, we assume that both track's endpoints are defined in the
-- intersections list and there are only two intersections.
function overlaps( t1, t2 )
	local t1x1, t1x2 = t1.intersections[ 1 ].x, t1.intersections[ 2 ].x
	local t2x1, t2x2 = t2.intersections[ 1 ].x, t2.intersections[ 2 ].x
	if t1x2 < t2x1 or t2x2 < t1x1 then
		return false
	else
		return true
	end
end

--- Add ridge markers to all up/down tracks, including the first and the last.
-- The last one does not need it but we'll take care of that once we know 
-- which track will really be the last one, because if we reverse the course
-- this changes.
--
function addRidgeMarkers( track )
	-- ridge markers should be on the unworked side so
	-- just check the turn at the end of the row.
	-- If it is a right turn then we start with the ridge marker on the right
	function getNextTurnDir(startIx)
		for i = startIx, #track do
			-- it is an up/down row if it has track number. Otherwise ignore turns
			if track[i].rowNumber and track[i].turnStart and track[i].deltaAngle then
				if track[i].deltaAngle >= 0 then
					return i, CourseGenerator.RIDGEMARKER_RIGHT
				else
					return i, CourseGenerator.RIDGEMARKER_LEFT
				end
			end
		end
		return nil
	end

	track:calculateData()
	local i = 1

	while (i < #track) do
		local startTurnIx, turnDirection = getNextTurnDir(i)
		if not startTurnIx then break end
		-- drive up to the next turn and add ridge markers where applicable
		while (i < startTurnIx) do
			-- don't use ridge markers at the first and the last row of the block as
			-- blocks can be worked in any order and we may screw up the adjacent block
			if track[i].rowNumber and not track[i].lastTrack and not track[i].firstTrack then
				if turnDirection == CourseGenerator.RIDGEMARKER_RIGHT then
					track[i].ridgeMarker = CourseGenerator.RIDGEMARKER_RIGHT
				else
					track[i].ridgeMarker = CourseGenerator.RIDGEMARKER_LEFT
				end
			end
			i = i + 1
		end
		-- we are at the start of the turn now, step over the turn start/end
		-- waypoints and work on the next row, find the next turn
		i = i + 2
	end
end

--- Make sure the last worked up down track does not have 
-- ridge markers.
-- Also, remove the ridge marker after the turn end so it is off
-- during the turn
function removeRidgeMarkersFromLastTrack( course, isReversed )
	for i, p in ipairs( course ) do
		-- if the course is not reversed (working on headland first)
		-- remove ridge markers from the last track
		if not isReversed and p.lastTrack then
			p.ridgeMarker = CourseGenerator.RIDGEMARKER_NONE
		end
		-- if it is reversed, the first track becomes the last
		if isReversed and p.firstTrack then
			p.ridgeMarker = CourseGenerator.RIDGEMARKER_NONE
		end
		-- if the previous wp is a turn end, remove
		-- (dunno why, this is how the old course generator works)
		if i > 1 and course[ i - 1 ].turnEnd then
			p.ridgeMarker = CourseGenerator.RIDGEMARKER_NONE
		end
	end
end

-- We are using a genetic algorithm to find the optimum sequence of the blocks to work on.
-- In case of a non-convex field or a field with island(s) in it, the field is divided into
-- multiple areas (blocks) which are covered by the up/down rows independently. 

-- We are looking for the optimum route to work these blocks, meaning the one with the shortest
-- path between the blocks. There are two factors determining the length of this path: 
-- 1. the sequence of blocks
-- 2. where do we start each block (which corner), which alse determines the exit corner of 
--    the block.
--
-- Most of this is based on the following paper:
-- Ibrahim A. Hameed, Dionysis Bochtis and Claus A. Sørensen: An Optimized Field Coverage Planning
-- Approach for Navigation of Agricultural Robots in Fields Involving Obstacle Areas

--- Composit chromosome for a field block to determine the best sequence of blocks 
FieldBlockChromosome = newClass()

function FieldBlockChromosome:new( nBlocks )
	local instance = {}
	local blockNumbers = {}
	-- array of +1 or -1. +1 at index 2 means that to reach the entry point of the second block
	-- from the exit point of the first you have to go increasing indexes on the headland.
	instance.directionToNextBlock = {}
	for i = 1, nBlocks do table.insert( blockNumbers, i ) end
	-- this chromosome has the sequence of blocks encoded
	instance.blockSequence = PermutationEncodedChromosome:new( nBlocks, blockNumbers )
	-- this chromosome has the entry point for each block encoded
	instance.entryCorner = ValueEncodedChromosome:new( nBlocks, { CourseGenerator.BLOCK_CORNER_BOTTOM_LEFT, CourseGenerator.BLOCK_CORNER_BOTTOM_RIGHT,
	                                                              CourseGenerator.BLOCK_CORNER_TOP_RIGHT, CourseGenerator.BLOCK_CORNER_TOP_LEFT })
	return setmetatable( instance, self )
end

function FieldBlockChromosome:__tostring()
	local str = ''
	for _, b in ipairs( self.blockSequence ) do
		str = string.format( '%s%d(%d)-', str, b, self.entryCorner[ b ])
	end
	if self.distance and self.fitness then
		str = string.format( '%s f = %.1f, d = %.1f m', str, self.fitness, self.distance )
	end
	return str
end

function FieldBlockChromosome:fillWithRandomValues()
	self.blockSequence:fillWithRandomValues()
	self.entryCorner:fillWithRandomValues()
end

function FieldBlockChromosome:crossover( spouse )
	local offspring = FieldBlockChromosome:new( #self.blockSequence )
	offspring.blockSequence = self.blockSequence:crossover( spouse.blockSequence )
	offspring.entryCorner = self.entryCorner:crossover( spouse.entryCorner )
	return offspring
end

function FieldBlockChromosome:mutate( mutationRate )
	self.blockSequence:mutate( mutationRate )
	self.entryCorner:mutate( mutationRate )
end

--- Find the (near) optimum sequence of blocks and entry/exit points.
-- NOTE: remmeber to call randomseed before. It isn't part of this function
-- to allow for automatic tests.
-- headland is the innermost headland pass.
--
function findBlockSequence( blocks, headland, circleStart, circleStep, nHeadlandPasses, nRowsToSkip )
	-- GA parameters, depending on the number of blocks
	local maxGenerations = 10 * #blocks
	local tournamentSize = 5
	local mutationRate = 0.03
	local populationSize = 40 * #blocks

	--- Calculate the fitness of a solution.
	--
	-- Calculate the distance to move between block exits and entrances for all 
	-- blocks in the given sequence. The fitness is the reciprocal of the distance
	-- so shorter routes are fitter.
	function calculateFitness( chromosome )
		chromosome.distance = 0
		for i = 1, #chromosome.blockSequence do
			local currentBlockIx = chromosome.blockSequence[ i ]
			local currentBlockExitCorner = getBlockExitCorner( chromosome.entryCorner[ currentBlockIx ], #blocks[ currentBlockIx ], nRowsToSkip )
			local currentBlockExitPoint = blocks[ currentBlockIx ].polygon[ currentBlockExitCorner ]
			-- in case of the first block we need to add the distance to drive from the end of the 
			-- innermost headland track to the entry point of the first block
			local distance, dir
			if i == 1 then
				local currentBlockEntryPoint = blocks[ currentBlockIx ].polygon[ chromosome.entryCorner[ currentBlockIx ]]
				-- TODO: this table comparison assumes the intersections were found on the same exact
				-- table instance as this upvalue headland. Ugly, should use some headland ID instead
				if headland == currentBlockEntryPoint.headland then
					if nHeadlandPasses > 0 then
						distance, dir = getDistanceBetweenPointsOnHeadland( headland, circleStart,
							currentBlockEntryPoint.headlandEdge.fromIx, { circleStep } )
					else
						-- if there is no headland, look for the closest point no matter what direction (as we can ignore the clockwise/ccw settings)
						distance, dir = getDistanceBetweenPointsOnHeadland( headland, circleStart,
							currentBlockEntryPoint.headlandEdge.fromIx, { -1, 1 } )
						--print(currentBlockIx, chromosome.entryCorner[currentBlockIx], distance, dir, circleStart, currentBlockEntryPoint.index)
					end
					chromosome.distance, chromosome.directionToNextBlock[ currentBlockIx ] = chromosome.distance + distance, dir
				else
					-- this block's entry point is not on the innermost headland (may be on an island)
					chromosome.distance, chromosome.directionToNextBlock[ currentBlockIx ] = math.huge, 1
				end
			end
			-- add the distance to the next block (except for the last)
			if i < #chromosome.blockSequence then
				local nextBlockIx = chromosome.blockSequence[ i + 1 ]
				local nextBlockEntryPoint = blocks[ nextBlockIx ].polygon[ chromosome.entryCorner[ nextBlockIx ]]
				if currentBlockExitPoint.headland == nextBlockEntryPoint.headland then
					-- can reach the next block on the same headland					
					distance, dir = getDistanceBetweenPointsOnHeadland(
						currentBlockExitPoint.headland, currentBlockExitPoint.headlandEdge.fromIx,
						nextBlockEntryPoint.headlandEdge.fromIx, { -1, 1 } )
					chromosome.distance, chromosome.directionToNextBlock[ currentBlockIx ] = chromosome.distance + distance, dir
				else
					-- next block's entry point is on a different headland, do not allow this by making
					-- this solution unfit
					chromosome.distance, chromosome.directionToNextBlock[ currentBlockIx ] = math.huge, 1
				end
			end
		end
		chromosome.fitness = ( 10000 / chromosome.distance )
		return chromosome.fitness
	end

	--- Distance when driving on a headland between is1 and is2. These are expected to be 
	-- intersection points with the headland stored. directions is a list of 
	-- values -1 or 1, and determines which directions we try to drive on the headland 
	function getDistanceBetweenPointsOnHeadland( headland, ix1, ix2, directions )
		local distanceMin = math.huge
		local directionMin = 0
		for _, d in ipairs( directions ) do
			local found = false
			local distance = 0
			for i in headland:iterator( ix1, ix1 - d, d ) do
				distance = distance + headland[ i ].nextEdge.length
				if i == ix2 then
					found = true
					break
				end
			end
			distance = found and distance or math.huge
			if distance < distanceMin then
				distanceMin = distance
				directionMin = d
			end
		end
		return distanceMin, directionMin
	end


	-- Set up the initial population with random solutions
	local population = Population:new( calculateFitness, tournamentSize, mutationRate )
	population:initialize( populationSize, function()
		local c = FieldBlockChromosome:new( #blocks )
		c:fillWithRandomValues()
		return c
	end )

	-- let the solution evolve through multiple generations
	population:calculateFitness()
	local generation = 1
	while generation < maxGenerations do
		local newGeneration = population:breed()
		population:recombine( newGeneration )
		generation = generation + 1
		CourseGenerator.debug( 'generation %d %s', generation, tostring( population.bestChromosome ))
	end
	CourseGenerator.debug( tostring( population.bestChromosome ))
	-- this table contains the blocks and other relevant data in the order they have to be worked on
	local blocksInSequence = {}
	for i = 1, #blocks do
		local blockIx = population.bestChromosome.blockSequence[ i ]
		local block = blocks[ blockIx ]
		block.entryCorner = population.bestChromosome.entryCorner[ blockIx ] -- corner where this block should be entered
		block.directionToNextBlock = population.bestChromosome.directionToNextBlock[ blockIx ] -- step direction on the headland index to take
		table.insert( blocksInSequence, block )
	end

	return blocksInSequence, population.bestChromosome
end

--- Get a list of waypoints on the headland between two edges (not waypoints!) as the start/end of
--- an up/down row is somewhere on that edge. To not to overshoot the up/down row, we want to have
--- the path between the inner waypoints of the two edges, like here, marked with a 'v':
---  start  v                                       v  end
---  x------x ..... x ..... x ..... x ..... x ..... x-----x
--- Depending on which direction we go travel on the headland (increasing or decreasing indices),
--- these may be the fromIx or the toIx of the edges. fromIx <= toIx is always true for both edges
---@param headland Polygon
---@param startingEdge table {fromIx, toIx}
---@param endingEdge table {fromIx, toIx}
---@param step number or nil, -1/+1 direction to follow on headland, default +1
function getTrackBetweenPointsOnHeadland( headland, startingEdge, endingEdge, step )
	local track = Polyline:new()

	local startIx, endIx
	if not step or step > 0 then
		startIx = startingEdge.toIx
		endIx = endingEdge.fromIx
	else
		startIx = startingEdge.fromIx
		endIx = endingEdge.toIx
	end
--	print(string.format('start %d - %d, end %d - %d => %d - %d',
--		startingEdge.fromIx, startingEdge.toIx, endingEdge.fromIx, endingEdge.toIx, startIx, endIx ))
	for i in headland:iterator( startIx, endIx, step ) do
		table.insert( track, headland[ i ])
	end
	return track
end

-- TODO: make sure this work with the spiral, circular and lands center patterns as well, where
-- the transition to the the up/down rows may not be in the corner
function linkBlocks( blocksInSequence, innermostHeadland, circleStart, firstBlockDirection, nRowsToSkip )
	local workedBlocks = {}
	for i, block in ipairs( blocksInSequence ) do
		if i == 1 then
			-- the track to the first block starts at the end of the innermost headland
			block.trackToThisBlock = getTrackBetweenPointsOnHeadland(innermostHeadland,
				{fromIx = circleStart, toIx = circleStart},
				block.polygon[ block.entryCorner ].headlandEdge, firstBlockDirection )
		end
		if i > 1 then
			-- for the rest of the blocks, the track to the block is from the exit point of the previous block
			local previousBlock = blocksInSequence[ i - 1 ]
			local previousBlockExitCorner = getBlockExitCorner( previousBlock.entryCorner, #previousBlock, nRowsToSkip )
			local headland = block.polygon[ block.entryCorner ].headland
			local previousOriginalTrackNumber = previousBlock.polygon[ previousBlockExitCorner ].originalRowNumber
			local thisOriginalTrackNumber = block.polygon[ block.entryCorner ].originalRowNumber
			-- Don't need a connecting track when these were originally adjacent tracks.
			if math.abs( previousOriginalTrackNumber - thisOriginalTrackNumber ) ~= 1 then
				block.trackToThisBlock = getTrackBetweenPointsOnHeadland( headland,
					previousBlock.polygon[ previousBlockExitCorner ].headlandEdge,
					block.polygon[ block.entryCorner ].headlandEdge, previousBlock.directionToNextBlock )
			else

			end
		end
		table.insert( workedBlocks, block )
	end
	return workedBlocks
end
