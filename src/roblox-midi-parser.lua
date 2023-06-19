-- // Types
type MidiData = {
	Format : number,
	TimeBase : number,
	Tempos : {
		[number] : {
			BPM : number,
			TempoTicks : number,
			Ticks : number,
			Time : number
		}
	},
	Tracks : {
		[number] : {
			Channel : number,
			Name : string,
			Ticks : number,
			Time : number
		}
	}
}

-- // Variables
local StudioService = game:GetService("StudioService")
local HTTPService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

local PackageSizes = {[8] = 2, [10] = 2, [11] = 2, [12] = 1, [13] = 1, [14] = 2}
local MetasThatIncrementBy1 = {47, 81, 88, 89}

local Toolbar = plugin:CreateToolbar("Midi Importer")
local ImportButton = Toolbar:CreateButton("Import", "Import a MIDI (.mid) file", "rbxassetid://1507949215", "Import MIDI File")
local ConvertToInstances = Toolbar:CreateButton("Convert", "Convert a ModuleScript returned from importing a midi file to StringValue instances", "rbxassetid://1507949215", "Convert To Instances")

-- // Internal Funcions
local ByteArray = function(Midi, Start, Length)
	local Table = {} 
	
	for i = 1, Length do
		Table[i] = string.byte( Midi, i + Start - 1 )
	end
	
	return Table
end
local BytesToNumber = function(Midi, Start, Length)
	local Number = 0
	
	for i = 1, Length do
		Number += string.byte(Midi, i + Start - 1) * math.pow(256, Length - i)
	end
	
	return Number
end
local VLQ = function(Midi, Start) -- Variable Length Quantity
	local Number = 0
	local Head = 0
	local Byte = 0
	
	repeat
		Byte = string.byte(Midi, Start + Head)
		Number = Number * 128 + (Byte - math.floor(Byte / 128) * 128)
		Head += 1
	until math.floor( Byte / 128 ) ~= 1
	
	return Number, Head
end
local IsSameTableShallow = function(a, b)
	for i,_ in a do
		if a[i] ~= b[i] then
			return false
		end
	end
	
	return true
end

-- // Main Functions
local ImportMidi = function(Midi)
	local Data = {
		Tracks = {},
		Tempos = {}
	}
	local Cursor = 1
	
	-- // Header Content
	
	assert(
		IsSameTableShallow(ByteArray(Midi, Cursor, 4), {77, 84, 104, 100}),
		"Input file is not .mid format"
	)
	
	Cursor += 8 -- header chunk magic number + length
	
	Data.Format = BytesToNumber(Midi, Cursor, 2)
	
	assert(
		Data.Format == 0 or Data.Format == 1,
		"This .mid file is not supported"
	)
	
	Cursor += 4 -- format + trackCount
	
	Data.TimeBase = BytesToNumber(Midi, Cursor, 2)
	
	Cursor += 2 -- timebase
	
	-- // "Fight Against .mid" - Original Library lol
	
	while Cursor < #Midi do
		-- // Checking if Chunk is Unknown
		if not IsSameTableShallow(ByteArray(Midi, Cursor, 4), {77, 84, 114, 107}) then
			Cursor += 8 + BytesToNumber(Midi, Cursor + 4, 4) -- unknown chunk magic number + chunk length + chunk data
			
			continue
		end
		
		-- // Track Header
		Cursor += 4 -- track chunk magic number
		
		local ChunkLength = BytesToNumber(Midi, Cursor, 4)
		
		Cursor += 4 -- chunk length
		
		local ChunkStart = Cursor
		
		-- // Data Variables
		local TicksPassed = 0
		local TrackName, TrackInstrument, TrackLyric = nil, nil, nil
		
		local Status = 0
		
		while Cursor < (ChunkStart + ChunkLength) do
			
			local DeltaTime, DeltaHead = VLQ(Midi, Cursor) -- timing
			
			Cursor += DeltaHead
			
			TicksPassed += DeltaTime
			
			local TempStatus = ByteArray(Midi, Cursor, 1)[1]
			if math.floor(TempStatus / 128) == 1 then
				Cursor += 1
				Status = TempStatus
			end
			
			local Type = math.floor(Status / 16)
			local Channel = Status - Type * 16
			
			if Type == 9 then
				local Package = ByteArray(Midi, Cursor, 2)
				
				Cursor += 2
				
				local TempoTicks = Data.Tempos[#Data.Tempos].TempoTicks
				local TimePerTick = TempoTicks / Data.TimeBase
				local SecPerTick = TimePerTick / 1000000
				local Time = TicksPassed * SecPerTick
				
				table.insert(Data.Tracks, {
					Ticks = TicksPassed,
					Time = Time,
					
					Name = TrackName,
					Instrument = TrackInstrument,
					Lyric = TrackLyric,
					
					Channel = Channel
				})
			elseif Status ~= 255 then
				Cursor += PackageSizes[Type]
			else -- meta event (lowest priority)
				local MetaType = ByteArray(Midi, Cursor, 1)[1]

				Cursor += 1
				
				local MetaLength, MetaHead = VLQ(Midi, Cursor)
				
				Cursor += table.find(MetasThatIncrementBy1, MetaType) ~= nil and 1 or MetaHead
				
				if MetaType == 3 then -- track name
					TrackName = string.sub(Midi, Cursor, Cursor + MetaLength - 1)
					
					Cursor += MetaLength
				elseif MetaType == 4 then -- instrument name
					TrackInstrument = string.sub(Midi, Cursor, Cursor + MetaLength - 1)
					
					Cursor += MetaLength
				elseif MetaType == 5 then -- lyric
					TrackLyric = string.sub(Midi, Cursor, Cursor + MetaLength - 1)
					
					Cursor += MetaLength
				elseif MetaType == 47 then -- end of track
					break
				elseif MetaType == 81 then -- tempo
					local TempoTicks = BytesToNumber(Midi, Cursor, 3)
					
					Cursor += 3
					
					local TimePerTick = TempoTicks / Data.TimeBase
					local SecPerTick = TimePerTick / 1000000
					local Time = TicksPassed * SecPerTick
					
					local BPM = 60 / (SecPerTick * Data.TimeBase)
					
					table.insert(Data.Tempos, {
						Ticks = TicksPassed,
						TempoTicks = TempoTicks,
						Time = Time,
						BPM = BPM
					})
				elseif MetaType == 88 then
					Cursor += 4
				elseif MetaType == 89 then
					Cursor += 2
				else
					Cursor += MetaLength
				end
			end
			
		end
		
	end
	
	table.sort(Data.Tracks, function(a, b)
		return a.Time < b.Time
	end)
	
	return Data
end

local ImportMidiFiles = function(IteratorFunction)
	local Midis = StudioService:PromptImportFiles({"mid"})

	assert(Midis ~= nil, "file/s went over the 100MB limit")

	for _,Midi in Midis do
		local FileName = Midi.Name
		
		Midi = Midi:GetBinaryContents()
		Midi = string.gsub(Midi, "\r\n", "\n")

		IteratorFunction(ImportMidi(Midi), FileName)
	end
end

ImportButton.Click:Connect(function()
	Selection:Set({})
	
	ImportMidiFiles(function(Data, FileName)
		local ModuleScript = Instance.new("ModuleScript")
		ModuleScript.Name = string.sub(FileName, 1, -5)
		ModuleScript.Source = `return table.freeze(game:GetService("HttpService"):JSONDecode([[{HTTPService:JSONEncode(Data)}]]))`
		ModuleScript.Parent = workspace
		
		Selection:Add({ModuleScript})
	end)
end)
ConvertToInstances.Click:Connect(function()
	local Selected = Selection:Get()
	
	Selection:Set({})
	
	for _,v in Selected do
		if typeof(v) ~= "Instance" then continue end
		if not v:IsA("ModuleScript") then continue end
		
		local Data = require(v)
		
		if typeof(Data) ~= "table" then continue end
		if Data.Tracks == nil then continue end
		
		local Folder = Instance.new("Folder")
		Folder.Name = v.Name
		
		local ChunksGenerated, CurrentChunk, CurrentChunkData = 1, Instance.new("StringValue", Folder), {}
		CurrentChunk.Name = `Chunk_{ChunksGenerated}`
		
		for _,x in Data.Tracks do
			table.insert(CurrentChunkData, x)
			
			if #CurrentChunkData >= 50 then
				ChunksGenerated += 1
				
				CurrentChunk.Value = HTTPService:JSONEncode(CurrentChunkData)
				CurrentChunkData = {}
				
				CurrentChunk = Instance.new("StringValue", Folder)
				CurrentChunk.Name = `Chunk_{ChunksGenerated}`
			end
		end
		
		CurrentChunk.Value = HTTPService:JSONEncode(CurrentChunkData)
		
		Folder.Parent = workspace
		
		Selection:Add({Folder})
	end
end)
