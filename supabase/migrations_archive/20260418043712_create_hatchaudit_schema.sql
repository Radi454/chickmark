-- 20260418043712 create_hatchaudit_schema
--
-- RECOVERED read-only from the production migration ledger
-- (supabase_migrations.schema_migrations.statements) on 2026-08-16. This
-- migration was applied to production but had no source file in the repo.
-- Content is verbatim; only this header comment was added.

-- TABLE: users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'auditor', 'customer')),
  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'suspended')),
  customer_id UUID REFERENCES customers(id),
  created_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  last_login_at TEXT
);

-- TABLE: customers
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  location TEXT,
  phone TEXT,
  email TEXT,
  created_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  created_by UUID REFERENCES users(id)
);

-- TABLE: flocks
CREATE TABLE IF NOT EXISTS flocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id),
  flock_id TEXT NOT NULL,
  breed TEXT NOT NULL CHECK (breed IN ('Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR')),
  entry_date TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
);

-- TABLE: audits (denormalized)
CREATE TABLE IF NOT EXISTS audits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_type TEXT NOT NULL CHECK (audit_type IN ('chick_quality', 'hatch_analysis', 'setter_optimizing', 'hatcher_optimizing', 'egg_storage')),
  customer_id UUID NOT NULL REFERENCES customers(id),
  flock_id UUID REFERENCES flocks(id),
  setter_id TEXT,
  hatcher_id TEXT,
  date TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'completed')),
  created_by UUID REFERENCES users(id),
  created_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  updated_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  notes TEXT,
  -- Chick Quality - CHA Environmental
  cha_govee_connected INTEGER,
  cha_co2 REAL,
  cha_co2_photo TEXT,
  cha_pm10 REAL,
  cha_pm10_photo TEXT,
  cha_pm25 REAL,
  cha_pm25_photo TEXT,
  cha_air_velocity_spot1 REAL,
  cha_air_velocity_spot1_photo TEXT,
  cha_air_velocity_spot2 REAL,
  cha_air_velocity_spot2_photo TEXT,
  cha_air_velocity_spot3 REAL,
  cha_air_velocity_spot3_photo TEXT,
  cha_air_inlet REAL,
  cha_air_inlet_photo TEXT,
  cha_air_outlet REAL,
  cha_air_outlet_photo TEXT,
  cha_noise_level REAL,
  cha_noise_level_photo TEXT,
  -- Chick Quality - Pasgar
  pasgar_sample_size INTEGER DEFAULT 40,
  pasgar_reflexes INTEGER,
  pasgar_reflexes_photo TEXT,
  pasgar_beak INTEGER,
  pasgar_beak_photo TEXT,
  pasgar_navel INTEGER,
  pasgar_navel_photo TEXT,
  pasgar_belly INTEGER,
  pasgar_belly_photo TEXT,
  pasgar_leg INTEGER,
  pasgar_leg_photo TEXT,
  pasgar_feather_dev INTEGER,
  pasgar_feather_dev_photo TEXT,
  pasgar_final_score REAL,
  -- Chick Quality - Weights
  chick_storage_days INTEGER DEFAULT 0,
  chick_sample_size INTEGER DEFAULT 100,
  chick_weights TEXT,
  chick_avg_weight REAL,
  chick_uniformity_pct REAL,
  chick_cv_pct REAL,
  chick_bmk_age INTEGER,
  chick_bmk_weight REAL,
  -- Chick Quality - YFBM
  yfbm_photo TEXT,
  yfbm_entries TEXT,
  yfbm_avg_pct REAL,
  yfbm_cv_pct REAL,
  -- Chick Quality - CVT
  cvt_sample_size INTEGER,
  cvt_top_basket TEXT,
  cvt_top_temp REAL,
  cvt_top_photo TEXT,
  cvt_middle_basket TEXT,
  cvt_middle_temp REAL,
  cvt_middle_photo TEXT,
  cvt_bottom_basket TEXT,
  cvt_bottom_temp REAL,
  cvt_bottom_photo TEXT,
  cvt_avg REAL,
  cvt_cv_pct REAL,
  -- Hatch Analysis - Hatch Results
  ha_storage_days INTEGER DEFAULT 0,
  ha_total_eggs_set INTEGER,
  ha_hatched INTEGER,
  ha_culled INTEGER,
  ha_dead INTEGER,
  ha_hatchability REAL,
  ha_fertility REAL,
  ha_hof REAL,
  ha_trays TEXT,
  ha_bmk_age INTEGER,
  -- Hatch Analysis - Egg Breakout
  eb_tray_size INTEGER DEFAULT 150,
  eb_breakout_type TEXT,
  eb_breakout_age_days INTEGER,
  eb_storage_days INTEGER DEFAULT 0,
  eb_trays TEXT,
  eb_bmk_age INTEGER,
  -- Setter Optimizing
  so_breed TEXT,
  so_setter_id TEXT,
  so_incubation_age INTEGER,
  so_govee_connected INTEGER,
  so_govee_temp REAL,
  so_govee_humidity REAL,
  so_co2 REAL,
  so_co2_photo TEXT,
  so_est_readings TEXT,
  so_est_photos TEXT,
  so_est_avg REAL,
  so_est_cv REAL,
  -- Hatcher Optimizing
  ho_breed TEXT,
  ho_hatcher_id TEXT,
  ho_incubation_age INTEGER,
  ho_govee_connected INTEGER,
  ho_govee_temp REAL,
  ho_govee_humidity REAL,
  ho_co2 REAL,
  ho_co2_photo TEXT,
  ho_cvt_readings TEXT,
  ho_cvt_photos TEXT,
  ho_cvt_avg REAL,
  ho_cvt_cv REAL,
  ho_chick_panting INTEGER,
  ho_chick_panting_photo TEXT,
  -- Egg Storage
  es_govee_connected INTEGER,
  es_govee_temp REAL,
  es_govee_humidity REAL,
  es_co2 REAL,
  es_co2_photo TEXT,
  es_shell_temp REAL,
  es_shell_temp_photo TEXT,
  es_turning_times INTEGER,
  es_uv_trays TEXT,
  es_egg_storage_days INTEGER DEFAULT 0,
  es_egg_sample_size INTEGER DEFAULT 100,
  es_egg_weights TEXT,
  es_egg_avg_weight REAL,
  es_egg_uniformity_pct REAL,
  es_egg_cv_pct REAL,
  es_egg_bmk_age INTEGER,
  es_egg_bmk_weight REAL
);

-- TABLE: bmk_breeds
CREATE TABLE IF NOT EXISTS bmk_breeds (
  breed TEXT NOT NULL,
  age_weeks INTEGER NOT NULL,
  hatchability_pct REAL,
  fertility_pct REAL,
  hof_pct REAL,
  production_pct REAL,
  egg_weight_g REAL,
  chick_weight_g REAL,
  PRIMARY KEY (breed, age_weeks)
);

-- TABLE: bmk_egg_breakout
CREATE TABLE IF NOT EXISTS bmk_egg_breakout (
  age_weeks INTEGER PRIMARY KEY,
  infertile REAL,
  early_dead_24h REAL,
  early_dead_48h REAL,
  blood_ring REAL,
  early_dead REAL,
  mid_black_eye REAL,
  feathers REAL,
  turned REAL,
  internal_pip REAL,
  late_dead REAL,
  external_pip REAL,
  exposed_brain REAL,
  crossed_beak REAL,
  contaminated REAL,
  cracked REAL
);

-- TABLE: troubleshooting
CREATE TABLE IF NOT EXISTS troubleshooting (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL CHECK (category IN ('egg_breakout', 'pasgar')),
  parameter TEXT NOT NULL,
  hatchery_causes TEXT,
  farm_flock_causes TEXT
);

-- TABLE: photos
CREATE TABLE IF NOT EXISTS photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID REFERENCES audits(id),
  field_key TEXT NOT NULL,
  file_path TEXT NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
);
