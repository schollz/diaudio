-- saich sing

musicutil=require("musicutil")

debug_mode=true
function dprint(name,...)
  if debug_mode then 
    print("["..name.."]",...)
  end
end

function init()
  -- settings
  local song_chords={"I","vi","IV","iii"} -- change to any chords
  local song_chord_length={8,8,8,8} -- beats for each chord
  local song_root=48
  local movement_left={6,6,6,6} -- change to 0-12
  local movement_right={6,6,6,6} -- change to 0-12
  local stay_on_chord={0.95,0.95,0.95,0.95} -- change to 0-1

  -- calculate chords
  local song_chord_notes={}
  local song_chord_quality={}
  for _, v in ipairs(song_chords) do 
    table.insert(song_chord_notes,musicutil.generate_chord_roman(song_root,1,v))
    table.inset(song_chord_quality,string.lower(v)==v and "minor" or "major")
  end
  local total_song_beats=0
  for _,v in ipairs(song_chord_length) do 
    total_song_beats=total_song_beats+v
  end

  local song_melody_notes={}
  local beat_chord=0
  local beat_chord_index=0
  local beat_melody=0
  local beat_last_note=0
  clock.run(function()
    while true do 
        clock.sync(1/2)
        -- iterate chord
        beat_chord=beat_chord%song_chord_length[beat_chord_index]+1
        if beat_chord==1 then 
            beat_chord_index=beat_chord_index%#song_chords+1
            if beat_chord_index==1 then 
              -- next phrase (new melody)
              song_melody_notes=generate_melody(total_song_beats,song_chords,song_root,movement_left,movement_right,stay_on_chord)
            end
            dprint("melody",string.format("next chord: %s",song_chords[beat_chord_index]))
            -- new chord
            crow.output[1].volts=(song_chord_notes[beat_chord_index][1]-24)/12
            crow.output[2].volts=song_chord_quality[beat_chord_index]=="major" and 10 or 0 -- TODO check if this is accurate
            -- new chord envelope
            local attack=clock.get_beat_sec()
            local decay=clock.get_beat_sec()
            local hold_time=(song_chord_length[beat_chord_index]*0.5)*clock.get_beat_sec()
            crow.output[3].action = string.format("{ to(0,0), to(10,%2.3f), to(7,%2.3f), to(0,%2.3f) }",attack,hold_time,decay)
            crow.output[3]()
        end
        -- iterate melody
        beat_melody=beat_melody%#song_melody_notes+1
        local next_note=song_melody_notes[beat_melody]
        if beat_last_note~=next_note then 
            crow.output[4].volts=(next_note-24)/12
            dprint("melody",string.format("next note: %d",next_note))
        end
        beat_last_note=next_note
    end
  end)
end

function generate_melody(total_beats,chord_structure,root_note,move_left,move_right,stay_scale)
  local factor=1

  -- notes to play
  local notes_to_play={}

  -- generate chords
  local chords={}
  for i,v in ipairs(chord_structure) do
    local scale=musicutil.generate_scale(12,1,8)
    local chord_notes=musicutil.generate_chord_roman(root_note,1,v)
    local notes_in_chord={}
    for _,u in ipairs(chord_notes) do
      notes_in_chord[u]=true
      for j=-5,5 do
        notes_in_chord[u+(12*j)]=true
      end
    end
    local note_start=chord_notes[1]
    for jj=1,4*factor do
      -- find note_start in scale
      local notes_to_choose={}
      for _,note in ipairs(scale) do
        if note>note_start-move_left[i] and note<note_start+move_right[i] then
          table.insert(notes_to_choose,note)
        end
      end
      local weights={}
      local scale_size=#notes_to_choose
      for i,note in ipairs(notes_to_choose) do
        weights[i]=notes_in_chord[note]~=nil and scale_size or scale_size*(1-util.clamp(stay_scale[i],0,1))
        -- weights[i]=weights[i]+(scale_size-i)
      end
      local note_next=choose_with_weights(notes_to_choose,weights)
      table.insert(notes_to_play,note_next)
      note_start=note_next
    end
  end

  return notes_to_play
end

function choose_with_weights(choices,weights)
  local totalWeight=0
  for _,weight in pairs(weights) do
    totalWeight=totalWeight+weight
  end

  local rand=math.random()*totalWeight
  local choice=nil
  for i,weight in pairs(weights) do
    if rand<weight then
      choice=choices[i]
      break
    else
      rand=rand-weight
    end
  end
  return choice
end