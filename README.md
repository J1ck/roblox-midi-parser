# roblox-midi-parser
Midi Parser Plugin for Roblox

## MIDI Data Type
```lua
type MIDIData = {
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
```

## Docs
|Button Name|Description|
|--|--|
|Import|Import a MIDI (.mid) file|
|Convert|Converts a ModuleScript returned by importing a MIDI file to StringValue Instances|
