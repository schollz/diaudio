-- diaudio

musicutil=require("musicutil")

engine.name="PolyPerc"

debug_mode=true
function dprint(name,...)
  if debug_mode then
    print("["..name.."]",...)
  end
end

local song_chord_possibilities={"I","ii","iii","IV","V","vi","vii"}
local total_chords=8
local song_chord_notes={}
local song_chord_quality={}

local select_param=1
local select_possible={{"chord_beats","stay_on_chord"},{"movement_left","movement_right"}}
local select_chord=1

History={}

function History.new(max_size)
  local hist={__index=History}
  setmetatable(hist,hist)
  hist.max_size=max_size
  hist.size=0
  hist.cursor=1
  return hist
end

function History:push(value)
  if self.size<self.max_size then
    table.insert(self,value)
    self.size=self.size+1
  else
    self[self.cursor]=value
    self.cursor=self.cursor%self.max_size+1
  end
end

function History:iterator()
  local i=0
  return function()
    i=i+1
    if i<=self.size then
      return i,self[(self.cursor-i-1)%self.size+1]
    end
  end
end

local marquee_chord=History.new(10)
local marquee_note=History.new(10)

function init()
  print("saich song")

  -- initialize arrays
  for i=1,total_chords do
    table.insert(song_chord_notes,0)
    table.insert(song_chord_quality,"major")
  end

  params:add_number("random_seed","random seed",1,1000000,18)
  params:add_taper("attack","attack",10,10000,100)
  params:add_taper("release","release",100,10000,1000)
  local params_menu={
    {id="chord",name="chord",min=1,max=7,exp=false,div=1,default=1,formatter=function(param) return song_chord_possibilities[param:get()] end},
    {id="root",name="root",min=1,max=120,exp=false,div=1,default=48,formatter=function(param) return musicutil.note_num_to_name(param:get(),true)end},
    {id="chord_beats",name="chord beats",min=1,max=32,exp=false,div=1,default=8,formatter=function(param) return string.format("%d beats",math.floor(param:get())) end},
    {id="stay_on_chord",name="stay on chord",min=0,max=1,exp=false,div=0.01,default=0.95,formatter=function(param) return string.format("%d%%",math.floor(param:get()*100)) end},
    {id="movement_left",name="movement left",min=0,max=12,exp=false,div=1,default=6,formatter=function(param) return string.format("<- %d",math.floor(param:get())) end},
    {id="movement_right",name="movement right",min=0,max=12,exp=false,div=1,default=6,formatter=function(param) return string.format("%d ->",math.floor(param:get())) end},
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
      if pram.id=="chord" then
        params:set_action(pram.id..i,function(x)
          local v=params:string("chord"..i)
          song_chord_notes[i]=musicutil.generate_chord_roman(params:get("root1"),1,v)
          song_chord_quality[i]=string.lower(v)==v and "minor" or "major"
        end)
      end
    end
  end
  -- default chords
  for i,v in ipairs({1,6,5,3,1,6,5,4}) do
    params:set("chord"..i,v)
    params:set("stay_on_chord"..i,math.random(90,97)/100)
    params:set("movement_left"..i,math.random(4,6))
    params:set("movement_right"..i,math.random(4,7))
  end
  local set_crow=function()
    crow.output[4].action=string.format("adsr(%2.3f,0.1,0.5,%2.3f)",params:get("attack")/1000,params:get("release")/1000)
  end
  params:set_action("attack",function(x)
    set_crow()
  end)
  params:set_action("release",function(x)
    set_crow()
  end)
  params:bang()

  local song_melody_notes={}
  local beat_chord=params:get("chord_beats"..total_chords)
  local beat_chord_index=total_chords
  local beat_melody=0
  local beat_last_note=0
  clock.run(function()
    clock.sleep(1)
    while true do
      clock.sync(1)

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
          local chord_beats={}
          local total_song_beats=0
          for i=1,total_chords do
            total_song_beats=total_song_beats+params:get("chord_beats"..i)
          end
          local song_root=params:get("root1") -- TODO fix this
          for i=1,4 do
            table.insert(song_chords,song_chord_possibilities[params:get("chord"..i)])
            table.insert(movement_left,params:get("movement_left"..i))
            table.insert(movement_right,params:get("movement_right"..i))
            table.insert(stay_on_chord,params:get("stay_on_chord"..i))
            table.insert(chord_beats,params:get("chord_beats"..i))
          end
          math.randomseed(os.time())
          params:set("random_seed",math.random(1,1000000))

          song_melody_notes=generate_melody(chord_beats,song_chords,song_root,movement_left,movement_right,stay_on_chord)
          -- print("new melody:")
          -- for i,v in ipairs(song_melody_notes) do
          --   print(i,musicutil.note_num_to_name(v),true)
          -- end
        end
        dprint("melody",string.format("next chord: %s",song_chord_possibilities[params:get("chord"..beat_chord_index)]))
        -- new chord
        for i=1,3 do
          engine.amp(0.3)
          engine.release(clock.get_beat_sec()*params:get("chord_beats"..beat_chord_index))
          engine.hz(musicutil.note_num_to_freq(song_chord_notes[beat_chord_index][i]))
        end
        crow.output[1].volts=(song_chord_notes[beat_chord_index][1]-24)/12
        crow.output[2].volts=(song_chord_notes[beat_chord_index][2]-24)/12
        crow.output[3].volts=(song_chord_notes[beat_chord_index][3]-24)/12
      end
      marquee_chord:push(params:string("chord"..beat_chord_index))

      -- iterate melody
      local note_next_name=""
      if next(song_melody_notes)~=nil then
        beat_melody=beat_melody%#song_melody_notes+1
        local next_note=song_melody_notes[beat_melody]
        if beat_last_note~=next_note then
          engine.amp(math.random(3,15)/10)
          engine.release(math.random(10,20)/10)
          engine.hz(musicutil.note_num_to_freq(next_note+12))
          crow.output[4].volts=(next_note-24)/12
          dprint("melody",string.format("next note: %d",next_note))
          note_next_name=musicutil.note_num_to_name(next_note,true)
        end
        beat_last_note=next_note
      end
      marquee_note:push(note_next_name)
      dprint("clock_run",string.format("chord beat %d, melody beat %d",beat_chord,beat_melody))
    end
  end)

  clock.run(function()
    while true do
      clock.sleep(1/10)
      redraw()
    end
  end)
end

function generate_melody(beats_per_chord,chord_structure,root_note,move_left,move_right,stay_scale)
  math.randomseed(params:get("random_seed"))
  local factor=1

  -- notes to play
  local notes_to_play={}

  -- generate chords
  local chords={}
  local scale=musicutil.generate_scale(12,1,8)
  local note_start=0
  for i,v in ipairs(chord_structure) do
    local chord_notes=musicutil.generate_chord_roman(root_note,1,v)
    if i==1 then
      note_start=chord_notes[1]
    end
    local notes_in_chord={}
    for _,u in ipairs(chord_notes) do
      notes_in_chord[u]=true
      for j=-5,5 do
        notes_in_chord[u+(12*j)]=true
      end
    end
    for jj=1,beats_per_chord[i] do
      -- find note_start in scale
      local notes_to_choose={}
      for _,note in ipairs(scale) do
        if note>note_start-move_left[i] and note<note_start+move_right[i] then
          table.insert(notes_to_choose,note)
        end
      end
      local weights={}
      local scale_size=#notes_to_choose
      for notei,note in ipairs(notes_to_choose) do
        weights[notei]=notes_in_chord[note]~=nil and scale_size or scale_size*(1-util.clamp(stay_scale[i],0,1))
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
    params:set("random_seed",math.random(1,1000000))
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
  screen.level(5)
  screen.move(120,5)
  screen.text_right(params:get("random_seed"))
  for i,v in ipairs(select_possible) do
    screen.level(select_param==i and 15 or 5)
    screen.move(32,10+12*i)
    screen.text_center(string.format("%s",params:string(v[1]..select_chord)))
    screen.move(96,10+12*i)
    screen.text_center(string.format("%s",params:string(v[2]..select_chord)))
  end
  screen.level(5)
  for i,v in marquee_chord:iterator() do
    screen.move(128-i*12,50)
    screen.text(v)
  end
  for i,v in marquee_note:iterator() do
    screen.move(128-i*12,60)
    screen.text(v)
  end
  screen.update()
end
