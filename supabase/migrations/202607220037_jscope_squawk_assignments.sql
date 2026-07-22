alter table public.tactical_instructions
  drop constraint if exists tactical_instructions_instruction_type_check;

alter table public.tactical_instructions
  add constraint tactical_instructions_instruction_type_check
  check (instruction_type in (
    'taxi','hold_position','runway_crossing','line_up_wait','takeoff','landing',
    'go_around','heading','altitude','speed','route','direct_to','hold',
    'approach_assignment','range_entry','range_exit','operating_area',
    'frequency_change','return_to_vatsim','squawk','advisory'
  ));

notify pgrst, 'reload schema';
