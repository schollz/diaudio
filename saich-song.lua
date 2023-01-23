-- saich sing

engine.name="PolyPerc"
musicutil=require("musicutil")

function init()

end


function init()
  -- settings
  local song_chords={"I","vi","IV","iii"} -- change to any chords
  local song_chord_length={4,4,4,4} -- beats for each chord
  local song_root=48

  -- calculate chords
  local song_chord_notes={}
  local song_chord_quality={}
  for _, v in ipairs(song_chords) do 
    table.insert(song_chord_notes,musicutil.generate_chord_roman(song_root,1,v))
    table.inset(song_chord_quality,string.lower(v)==v and "minor" or "major")
  end

  -- calculate total beats
  local song_beats=0
  for _,v in ipairs(song_chord_length) do 
    song_beats=song_beats+v
  end

  -- calculate melody (TODO)
  song_melody_notes={48}
--   local movement_left=6 -- change to 0-12
--   local movement_right=6 -- change to 0-12
--   local stay_on_chord=0.95 -- change to 0-1
--   play(chords,1,movement_left,movement_right,stay_on_chord)

  local beat_chord=0
  local beat_chord_index=1
  local beat_melody=0
  local beat_last_note=0
  clock.run(function()
    while true do 
        clock.sync(1)
        -- iterate chord
        beat_chord=beat_chord%song_chord_length[beat_chord_index]+1
        if beat_chord==1 then 
            beat_chord_index=beat_chord_index%#song_chords+1
            -- new chord
            crow.output[1].volts=(song_chord_notes[beat_chord_index][1]-24)/12
            crow.output[2].volts=song_chord_quality[beat_chord_index]=="major" and 10 or 0
            -- TODO: update envelope envelope
            crow.output[3]()
        end
        -- iterate melody
        beat_melody=beat_melody%#song_melody_notes+1
        local next_note=song_melody_notes[beat_melody]
        if beat_last_note~=next_note then 
            crow.output[4].volts=(next_note-24)/12
        end
        beat_last_note=next_note
    end

  end)

end

function play(chord_structure,factor,move_left,move_right,stay_scale)
  stay_scale=util.clamp(stay_scale,0,1)
  -- notes to play
  local notes_to_play={}

  -- generate chords
  local chords={}
  for i,v in ipairs(chord_structure) do
    local scale=musicutil.generate_scale(12,1,8)
    local chord_notes=musicutil.generate_chord_roman(12,1,v)
    local notes_in_chord={}
    for _,u in ipairs(chord_notes) do
      notes_in_chord[u]=true
      for j=1,8 do
        notes_in_chord[u+(12*j)]=true
      end
    end
    local note_start=72
    for jj=1,4*factor do
      -- find note_start in scale
      local notes_to_choose={}
      for _,note in ipairs(scale) do
        if note>note_start-move_left and note<note_start+move_right then
          table.insert(notes_to_choose,note)
        end
      end
      local weights={}
      local scale_size=#notes_to_choose
      for i,note in ipairs(notes_to_choose) do
        weights[i]=notes_in_chord[note]~=nil and scale_size or scale_size*(1-stay_scale)
        -- weights[i]=weights[i]+(scale_size-i)
      end
      local note_next=choose_with_weights(notes_to_choose,weights)
      table.insert(notes_to_play,note_next)
      note_start=note_next
    end
  end

  return notes_to_play

--   local notei=0
--   local note_last=0
--   clock.run(function()
--     while true do
--       clock.sync(1/factor)
--       notei=(notei)%#notes_to_play+1
--       local note_next=notes_to_play[notei]
--       if note_next~=note_last then
--         engine.hz(musicutil.note_num_to_freq(note_next))
--       end
--       note_last=note_next
--     end
--   end)
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