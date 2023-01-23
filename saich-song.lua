-- saich sing

musicutil=require("musicutil")

debug_mode=true
function dprint(name,...)
  if debug_mode then 
    print("["..name.."]",...)
  end
end

local song_chord_possibilities={"I","ii","iii","IV","V","vi","vii"}
local total_chords=4
local song_chord_notes={}
local song_chord_quality={}

local select_param=1
local select_possible={{"chord_beats","stay_on_chord"},{"movement_left","movement_right"}}
local select_chord=1

function init()
  -- initialize arrays
  for i=1,total_chords
    table.insert(song_chord_notes,0)
    table.insert(song_chord_quality,"major")
  end

  local params_menu={
    {id="chord",name="chord",min=1,max=7,exp=false,div=1,default=1,formatter=function(param) return song_chord_possibilities[param:get()] end},
    {id="root",name="root",min=1,max=120,exp=false,div=1,default=48,formatter=function(param) return musicutil.note_num_to_name(param:get(),true)end},
    {id="chord_beats",name="chord beats",min=1,max=32,exp=false,div=1,default=8,unit="beats"},
    {id="stay_on_chord",name="stay on chord",min=0,max=1,exp=false,div=0.01,default=0.95,formatter=function(param) return string.format("%d",math.floor(params:get()*100)) end},
    {id="movement_left",name="movement left",min=0,max=12,exp=false,div=1,default=6,unit="notes"},
    {id="movement_right",name="movement right",min=0,max=12,exp=false,div=1,default=6,unit="notes"},
  }
  for i=1,total_chords do 
    for _,pram in ipairs(params_menu) do
        params:add{
          type="control",
          id=pram.id..i,
          name=pram.name,
          controlspec=controlspec.new(pram.min,pram.max,pram.exp and "exp" or "lin",pram.div,pram.default,pram.unit or "",pram.div/(pram.max-pram.min)),
          formatter=pram.formatter,
        }
        if pramd.id=="chord" then 
          params:set_action(pram.id..i,function(x)
            local v=params:string("chord"..i)
            song_chord_notes[i]=musicutil.generate_chord_roman(song_root,1,v)
            song_chord_quality[i]=string.lower(v)==v and "minor" or "major"
          end)
        end
    end
  end
  -- default chords
  for i, v in ipairs({1,6,4,3}) do 
    params:set("chord"..i,v)
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
        beat_chord=beat_chord%params:get("chord_beats"..beat_chord_index)+1
        if beat_chord==1 then 
            beat_chord_index=beat_chord_index%total_chords+1
            if beat_chord_index==1 then 
              -- next phrase (new melody)
              local movement_left={}
              local movement_right={}
              local stay_on_chord={}
              local song_chords={}
              local total_song_beats=0
              for i=1,total_chords
                total_song_beats=total_song_beats+params:get("chord_beats"..i)
              end
              for i=1,4 do 
                table.insert(song_chords,song_chord_possibilities[params:get("chord"..i)])
                table.insert(movement_left,params:get("movement_left"..i))
                table.insert(movement_right,params:get("movement_right"..i))
                table.insert(stay_on_chord,params:get("stay_on_chord"..i))
              end
              song_melody_notes=generate_melody(total_song_beats,song_chords,song_root,movement_left,movement_right,stay_on_chord)
            end
            dprint("melody",string.format("next chord: %s",song_chord_possibilities[params:get("chord"..beat_chord_index]))
            -- new chord
            crow.output[1].volts=(song_chord_notes[beat_chord_index][1]-24)/12
            crow.output[2].volts=song_chord_quality[beat_chord_index]=="major" and 10 or 0 -- TODO check if this is accurate
            -- new chord envelope
            local attack=clock.get_beat_sec()
            local decay=clock.get_beat_sec()
            local hold_time=(params:get("chord_beats"..beat_chord_index)*0.5)*clock.get_beat_sec()
            crow.output[3].action = string.format("{ to(0,0), to(10,%2.3f), to(7,%2.3f), to(0,%2.3f) }",attack,hold_time,decay)
            crow.output[3]()
        end

        -- iterate melody
        if next(song_melody_notes)~=nil then 
          beat_melody=beat_melody%#song_melody_notes+1
          local next_note=song_melody_notes[beat_melody]
          if beat_last_note~=next_note then 
              crow.output[4].volts=(next_note-24)/12
              dprint("melody",string.format("next note: %d",next_note))
          end
          beat_last_note=next_note
        end
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
    local chord_notes=musicutil.generate_chord_roman(root_note,1,song_chord_possibilities[v])
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

function key(k,z)
  if k==2 and z==1 then 
    select_param=util.wrap(select_param+1,1,2)
  elseif k==3 and z==1 then 
  end
end

function enc(k,d)
  if k==1 then 
    select_chord=util.wrap(select_chord+d,1,total_chords)
  else
    params:delta(select_possible[select_param][k-1]..select_chord,d)
  end
end

function redraw()
  screen.clear()
  for i=1,total_chords do 
    screen.move(5+(i*10),5)
    screen.level(select_chord==i and 15 or 5)
    screen.text_center(params:string("chord"..i))
  end
  for i,v in ipairs(select_possible) do 
    screen.move(64,20+12*i)
    screen.level(select_param==i and 15 or 5)
    screen.text_center(string.format("%s: %s    %s: %s",v[1],params:string(v[1]..select_chord,v[2],params:string(v[2]..select_chord))))
  end
  screen.update()
end