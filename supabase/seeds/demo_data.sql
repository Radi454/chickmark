-- Comprehensive demo dataset for the ChickMark cloud DB.
-- Apply against a schema built by supabase/migrations/0001 + 0002.
-- All rows use readable text ids and snake_case columns (mirrors the app).
-- Pulled into the app by StartupSyncService on login/Sync Now.

insert into public.bmk_breeds (id,breed,age_week,hatchability_pct,fertility_pct,hof_pct,production_pct,egg_weight_g,chick_weight_g) values
 ('bmk-ross-30','Ross 308',30,92.1,96.5,88.9,84.0,58.2,40.1),
 ('bmk-ross-45','Ross 308',45,89.4,95.0,84.9,78.5,66.0,45.2),
 ('bmk-ross-60','Ross 308',60,84.7,92.1,78.0,68.0,71.3,48.6),
 ('bmk-cobb-30','Cobb 500',30,91.5,96.0,87.8,83.2,57.0,39.5),
 ('bmk-cobb-45','Cobb 500',45,88.9,94.6,84.1,77.9,65.1,44.7),
 ('bmk-cobb-60','Cobb 500',60,83.9,91.5,76.8,67.2,70.4,48.0);

insert into public.bmk_egg_breakout (id,age_week,infertile_pct,early24h_pct,early48h_pct,blood_ring_pct,black_eye_pct,early_dead_pct,mid_dead_pct,late_dead_pct,external_pip_pct,cracked_pct,contam_pct) values
 ('beb-30',30,3.5,1.2,0.9,0.6,0.8,2.1,1.0,1.6,0.7,0.5,0.4),
 ('beb-45',45,5.0,1.5,1.1,0.8,1.0,2.6,1.3,2.0,0.9,0.7,0.6),
 ('beb-60',60,7.8,2.0,1.6,1.1,1.4,3.4,1.8,2.7,1.2,1.0,0.9);

insert into public.customers (id,name,location,phone,email,created_at,created_by) values
 ('cust-nilevalley','Nile Valley Farms','Cairo, EG','+20100100100','ops@nilevalley.example','2025-08-01T08:00:00.000',null),
 ('cust-deltapoultry','Delta Poultry Co.','Mansoura, EG','+20100200200','contact@deltapoultry.example','2025-08-03T08:00:00.000',null),
 ('cust-sunrise','Sunrise Hatchery','Alexandria, EG','+20100300300','hello@sunrise.example','2025-08-05T08:00:00.000',null);

insert into public.hatcheries (id,customer_id,name,location,notes,created_at,created_by) values
 ('hatch-nv-giza','cust-nilevalley','Giza Hatchery','Giza','Main site','2025-08-02T08:00:00.000',null),
 ('hatch-delta-main','cust-deltapoultry','Delta Main Hatchery','Mansoura',null,'2025-08-04T08:00:00.000',null),
 ('hatch-sunrise-1','cust-sunrise','Sunrise Plant 1','Alexandria',null,'2025-08-06T08:00:00.000',null);

insert into public.flocks (id,customer_id,flock_id,breed,entry_date,is_age_estimated,status,depletion_age_weeks,sold_at) values
 ('flock-nv-01','cust-nilevalley','NV-FL-01','Ross 308','2025-09-01T00:00:00.000',0,'active',65,null),
 ('flock-nv-02','cust-nilevalley','NV-FL-02','Cobb 500','2025-06-15T00:00:00.000',1,'active',65,null),
 ('flock-delta-01','cust-deltapoultry','DL-FL-01','Ross 308','2025-11-01T00:00:00.000',0,'active',65,null),
 ('flock-delta-02','cust-deltapoultry','DL-FL-02','Cobb 500','2025-03-10T00:00:00.000',0,'sold',65,'2026-05-01T00:00:00.000'),
 ('flock-sunrise-01','cust-sunrise','SR-FL-01','Ross 308','2025-12-20T00:00:00.000',0,'active',65,null);

insert into public.audit_sessions (id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,status,selected_station_keys,stations_completed,notes,created_by,created_at,updated_at,completed_at) values
 ('as-01','cust-nilevalley','flock-nv-01','hatch-nv-giza','2026-05-20T00:00:00.000','Ross 308',37,'completed','["egg_storage","chick_quality"]','["egg_storage","chick_quality"]','Routine visit','seed','2026-05-20T09:00:00.000','2026-05-20T12:00:00.000','2026-05-20T12:00:00.000'),
 ('as-02','cust-nilevalley','flock-nv-02','hatch-nv-giza','2026-05-22T00:00:00.000','Cobb 500',49,'in_progress','["egg_storage"]',null,null,'seed','2026-05-22T09:00:00.000','2026-05-22T09:30:00.000',null),
 ('as-03','cust-deltapoultry','flock-delta-01','hatch-delta-main','2026-05-18T00:00:00.000','Ross 308',28,'completed','["egg_storage","fresh_egg_breakout"]','["egg_storage","fresh_egg_breakout"]','Breakout done','seed','2026-05-18T08:00:00.000','2026-05-18T11:00:00.000','2026-05-18T11:00:00.000'),
 ('as-04','cust-deltapoultry','flock-delta-02','hatch-delta-main','2026-04-30T00:00:00.000','Cobb 500',60,'completed','["candled_egg_breakout","residue_breakout"]','["candled_egg_breakout","residue_breakout"]','End of cycle','seed','2026-04-30T08:00:00.000','2026-04-30T13:00:00.000','2026-04-30T13:00:00.000'),
 ('as-05','cust-sunrise','flock-sunrise-01','hatch-sunrise-1','2026-06-01T00:00:00.000','Ross 308',24,'in_progress','["setter_optimizing","hatcher_optimizing"]',null,null,'seed','2026-06-01T08:00:00.000','2026-06-01T09:00:00.000',null);

insert into public.egg_storage (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,house,storage_period_days,bmk_age_weeks,created_at,updated_at,sync_status,est_avg,est_cv_pct,shell_temp,turning_times,condensation_present,upside_down_count,upside_down_pct) values
 ('es-01','as-01','cust-nilevalley','flock-nv-01','hatch-nv-giza','2026-05-20T00:00:00.000','Ross 308',37,'H1',3,37,'2026-05-20T09:10:00.000','2026-05-20T09:10:00.000','synced',18.4,1.1,20.2,2,0,1,2.0),
 ('es-02','as-03','cust-deltapoultry','flock-delta-01','hatch-delta-main','2026-05-18T00:00:00.000','Ross 308',28,'H2',2,28,'2026-05-18T08:10:00.000','2026-05-18T08:10:00.000','synced',18.7,0.9,19.8,3,0,0,0.0);

insert into public.chick_quality (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,setter,hatcher,created_at,updated_at,sync_status,pasgar_sample_size,pasgar_final_score,yfbm_avg_pct,cvt_avg_temp,cvt_cv_pct) values
 ('cq-01','as-01','cust-nilevalley','flock-nv-01','hatch-nv-giza','2026-05-20T00:00:00.000','Ross 308',37,'S1','HT1','2026-05-20T10:30:00.000','2026-05-20T10:30:00.000','synced',40,9.2,64.5,40.1,1.4);

insert into public.fresh_egg_breakout (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,house,created_at,updated_at,sync_status,tray_size,infertile_count,early24h_count,blood_ring_count,infertile_pct,early24h_pct,blood_ring_pct) values
 ('feb-01','as-03','cust-deltapoultry','flock-delta-01','hatch-delta-main','2026-05-18T00:00:00.000','Ross 308',28,'H2','2026-05-18T08:30:00.000','2026-05-18T08:30:00.000','synced',150,6,3,1,4.0,2.0,0.7);

insert into public.candled_egg_breakout (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,trolley,created_at,updated_at,sync_status,candling_day,tray_size,infertile_count,blood_ring_count,black_eye_count,infertile_pct) values
 ('ceb-01','as-04','cust-deltapoultry','flock-delta-02','hatch-delta-main','2026-04-30T00:00:00.000','Cobb 500',60,'T3','2026-04-30T10:00:00.000','2026-04-30T10:00:00.000','synced',18,150,12,3,4,8.0);

insert into public.residue_breakout (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,trolley,created_at,updated_at,sync_status,tray_size,total_eggs_set,hatched_count,hatchability_pct,fertility_pct,hof_pct) values
 ('rb-01','as-04','cust-deltapoultry','flock-delta-02','hatch-delta-main','2026-04-30T00:00:00.000','Cobb 500',60,'T3','2026-04-30T10:30:00.000','2026-04-30T10:30:00.000','synced',150,144,118,81.9,90.3,90.8);

insert into public.setter_optimizing (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,setter,created_at,updated_at,sync_status,machine_type,setpoint_f,actual_f,setpoint_rh,actual_rh,co2_ppm,incubation_age_days) values
 ('so-01','as-05','cust-sunrise','flock-sunrise-01','hatch-sunrise-1','2026-06-01T00:00:00.000','Ross 308',24,'S1','2026-06-01T08:20:00.000','2026-06-01T08:20:00.000','synced','Single-stage',99.5,99.6,55.0,54.4,3800,10);

insert into public.hatcher_optimizing (id,session_id,customer_id,flock_id,hatchery_id,date,breed,flock_age_weeks,hatcher,created_at,updated_at,sync_status,setpoint_f,setpoint_rh,co2_ppm,cvt_avg,chick_panting,transfer_day) values
 ('ho-01','as-05','cust-sunrise','flock-sunrise-01','hatch-sunrise-1','2026-06-01T00:00:00.000','Ross 308',24,'HT1','2026-06-01T08:40:00.000','2026-06-01T08:40:00.000','synced',98.6,60.0,5200,40.2,0,18);

insert into public.govee_daily_captures (id,customer_id,hatchery_id,station_key,place,machine_id,capture_date,status,reading_count,chart_points_json,created_at,updated_at,temp_avg,temp_min,temp_max,rh_avg,rh_min,rh_max,temp_cv_pct,rh_cv_pct) values
 ('gv-01','cust-nilevalley','hatch-nv-giza','S1','setter','M1','2026-05-20','complete',144,'[]','2026-05-20T09:00:00.000','2026-05-20T09:00:00.000',37.6,37.2,38.0,55.1,53.0,57.0,0.6,1.2),
 ('gv-02','cust-deltapoultry','hatch-delta-main','HT1','hatcher','MH1','2026-05-18','complete',120,'[]','2026-05-18T08:00:00.000','2026-05-18T08:00:00.000',36.9,36.5,37.4,62.0,60.0,64.0,0.7,1.5),
 ('gv-03','cust-sunrise','hatch-sunrise-1','S1','setter','M1','2026-06-01','complete',96,'[]','2026-06-01T08:00:00.000','2026-06-01T08:00:00.000',37.7,37.3,38.1,54.5,52.5,56.5,0.5,1.1);

insert into public.photos (id,file_path,description,created_at,session_id,panel_name,panel_row_id,field_key,upload_status) values
 ('ph-01','supabase://photos/as-01/egg_storage/es-01/shell.jpg','Shell temp reading','2026-05-20T09:12:00.000','as-01','egg_storage','es-01','shell_temp','synced'),
 ('ph-02','supabase://photos/as-03/fresh_egg_breakout/feb-01/tray.jpg','Breakout tray','2026-05-18T08:15:00.000','as-03','fresh_egg_breakout','feb-01','tray_size','synced');
