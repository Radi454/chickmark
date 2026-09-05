# Chick Quality V2 Phase 5 Cleanup Audit

This report is generated from the canonical station registry, conservative production-source search evidence, and the checked-in cleanup evidence.

## Decision

**RETAIN** — no compatibility structures were removed.

## Safety gates

| Gate | Proven | Evidence |
| --- | --- | --- |
| Zero production runtime readers/writers proven | no | 947 conservative token mention(s) and 7 heuristically detected registry-driven consumer(s) found. Inventory completeness: no — The lexical and heuristic scans are conservative aids, not a complete Dart/TypeScript call graph; indirect or aliased registry-driven readers such as panel_row_to_draft.dart require an explicit reviewed inventory before zero readers can be proven. |
| Every persisted row has a safe V2 replacement | no | Coverage of every persisted row is unproven; Phase 4 intentionally leaves some untouched or malformed legacy rows without normalized children, so their compatibility caches may still be the only copy of user evidence. |
| Backward compatibility has been released | no | Current clients dual-write compatibility caches and observation-first reads still fall back to them for mixed-version and legacy data. |
| A lossless local/cloud removal migration is ready | no | No local or cloud proof shows every retained cache is redundant, and no live Supabase migration is authorized in this work. |

## Registry-derived compatibility vocabulary

- `avgWeight`
- `avg_weight`
- `chicks.legacy_combined`
- `culledChicksAffectedPct`
- `culledChicksAnalysisJson`
- `culledChicksTopCategory`
- `culledChicksTopSubtype`
- `culledChicksTotalEggSet`
- `culled_chicks_affected_pct`
- `culled_chicks_analysis_json`
- `culled_chicks_top_category`
- `culled_chicks_top_subtype`
- `culled_chicks_total_egg_set`
- `cvPct`
- `cv_pct`
- `cvtAvgTemp`
- `cvtCvPct`
- `cvtReadingsJson`
- `cvtSampleSize`
- `cvt_avg_temp`
- `cvt_cv_pct`
- `cvt_readings_json`
- `cvt_sample_size`
- `pasgarBeakCount`
- `pasgarBeakPct`
- `pasgarBellyCount`
- `pasgarBellyPct`
- `pasgarFeatherDevCount`
- `pasgarFeatherDevPct`
- `pasgarFinalScore`
- `pasgarLegCount`
- `pasgarLegPct`
- `pasgarNavelCount`
- `pasgarNavelPct`
- `pasgarReflexesCount`
- `pasgarReflexesPct`
- `pasgarSampleSize`
- `pasgar_beak_count`
- `pasgar_beak_pct`
- `pasgar_belly_count`
- `pasgar_belly_pct`
- `pasgar_feather_dev_count`
- `pasgar_feather_dev_pct`
- `pasgar_final_score`
- `pasgar_leg_count`
- `pasgar_leg_pct`
- `pasgar_navel_count`
- `pasgar_navel_pct`
- `pasgar_reflexes_count`
- `pasgar_reflexes_pct`
- `pasgar_sample_size`
- `pmAirSacCaseationsCount`
- `pmAirSacCaseationsSeverity`
- `pmCollectionPoint`
- `pmGaseousCecaCount`
- `pmGaseousCecaSeverity`
- `pmGeneralSepticemiaCount`
- `pmGeneralSepticemiaSeverity`
- `pmGizzardErosionsCount`
- `pmGizzardErosionsSeverity`
- `pmNephritisCount`
- `pmNephritisSeverity`
- `pmOmphalitisCount`
- `pmOmphalitisSeverity`
- `pmSampleSize`
- `pmUrolithiasisCount`
- `pmUrolithiasisSeverity`
- `pm_air_sac_caseations_count`
- `pm_air_sac_caseations_severity`
- `pm_collection_point`
- `pm_gaseous_ceca_count`
- `pm_gaseous_ceca_severity`
- `pm_general_septicemia_count`
- `pm_general_septicemia_severity`
- `pm_gizzard_erosions_count`
- `pm_gizzard_erosions_severity`
- `pm_nephritis_count`
- `pm_nephritis_severity`
- `pm_omphalitis_count`
- `pm_omphalitis_severity`
- `pm_sample_size`
- `pm_urolithiasis_count`
- `pm_urolithiasis_severity`
- `sampleSize`
- `sample_size`
- `uniformityPct`
- `uniformity_pct`
- `weightsJson`
- `weights_json`
- `yfbmAvgPct`
- `yfbmCvPct`
- `yfbmEntriesJson`
- `yfbmEntryCount`
- `yfbm_avg_pct`
- `yfbm_cv_pct`
- `yfbm_entries_json`
- `yfbm_entry_count`

## Heuristically detected registry-driven consumers

- `lib/data/agent/chick_quality_classifier.dart`
- `lib/data/agent/station_adapter.dart`
- `lib/data/repositories/panel_sample_repository.dart`
- `lib/features/audits/logic/chick_registry_validation.dart`
- `lib/features/audits/logic/panel_value_builders.dart`
- `supabase/functions/telegram-hatchery-agent/agent_read_tools.ts`
- `supabase/functions/telegram-hatchery-agent/agent_station_adapter.ts`

## Conservative production token mentions

These lexical mentions are cleanup blockers, not claims that every line is a Chick reader or writer. Comments, writes, and unrelated domains can appear here; a future cleanup must classify and eliminate them before the zero-reader proof can pass.

### `lib/core/utils/calculation_utils.dart`

- line 25: `sampleSize`
- line 26: `sampleSize`
- line 29: `sampleSize`
- line 31: `sampleSize`
- line 178: `sampleSize`
- line 179: `sampleSize`
- line 180: `sampleSize`

### `lib/core/utils/field_validators.dart`

- line 45: `sampleSize`
- line 77: `sampleSize`
- line 82: `sampleSize`

### `lib/data/agent/chick_quality_classifier.dart`

- line 20: `chicks.legacy_combined`
- line 40: `chicks.legacy_combined`
- line 62: `chicks.legacy_combined`

### `lib/data/agent/station_adapter.dart`

- line 631: `yfbm_entry_count`
- line 633: `yfbm_cv_pct`

### `lib/data/database/database_helper.dart`

- line 526: `cvPct`

### `lib/data/database/database_migrations.dart`

- line 750: `weightsJson`
- line 884: `chicks.legacy_combined`
- line 1050: `cvtReadingsJson`
- line 1054: `cvtAvgTemp`
- line 1059: `cvtReadingsJson`
- line 1078: `cvtReadingsJson`
- line 1087: `cvtAvgTemp`

### `lib/data/database/database_schema.dart`

- line 839: `cvPct`
- line 2490: `sampleSize`
- line 2535: `sampleSize`
- line 2827: `cv_pct`
- line 2827: `uniformity_pct`
- line 2839: `cv_pct`
- line 2839: `uniformity_pct`
- line 2901: `cv_pct`
- line 2901: `uniformity_pct`

### `lib/data/database/seeds/breeder_alert_rule_seeds.dart`

- line 83: `uniformity_pct`
- line 84: `uniformityPct`
- line 102: `cv_pct`
- line 103: `cvPct`

### `lib/data/database/seeds/dashboard_demo_seeds.dart`

- line 305: `avgWeight`
- line 348: `cvtReadingsJson`
- line 568: `pasgarSampleSize`
- line 569: `pasgarFinalScore`
- line 570: `pasgarReflexesCount`
- line 571: `pasgarReflexesPct`
- line 572: `pasgarBeakCount`
- line 573: `pasgarBeakPct`
- line 574: `pasgarNavelCount`
- line 575: `pasgarNavelPct`
- line 576: `pasgarBellyCount`
- line 577: `pasgarBellyPct`
- line 578: `pasgarLegCount`
- line 579: `pasgarLegPct`
- line 580: `pasgarFeatherDevCount`
- line 581: `pasgarFeatherDevPct`
- line 582: `cvtSampleSize`
- line 583: `cvtReadingsJson`
- line 584: `cvtAvgTemp`
- line 585: `cvtCvPct`
- line 586: `yfbmAvgPct`
- line 591: `pasgarSampleSize`
- line 592: `pasgarFinalScore`
- line 593: `pasgarReflexesCount`
- line 594: `pasgarReflexesPct`
- line 595: `pasgarBeakCount`
- line 596: `pasgarBeakPct`
- line 597: `pasgarNavelCount`
- line 598: `pasgarNavelPct`
- line 599: `pasgarBellyCount`
- line 600: `pasgarBellyPct`
- line 601: `pasgarLegCount`
- line 602: `pasgarLegPct`
- line 603: `pasgarFeatherDevCount`
- line 604: `pasgarFeatherDevPct`
- line 605: `cvtSampleSize`
- line 606: `cvtReadingsJson`
- line 607: `cvtAvgTemp`
- line 608: `cvtCvPct`
- line 609: `yfbmAvgPct`
- line 617: `sampleSize`
- line 618: `weightsJson`
- line 619: `avgWeight`
- line 620: `uniformityPct`
- line 621: `cvPct`
- line 626: `sampleSize`
- line 627: `weightsJson`
- line 628: `avgWeight`
- line 629: `uniformityPct`
- line 630: `cvPct`
- line 709: `cvtSampleSize`
- line 710: `cvtReadingsJson`
- line 712: `cvtCvPct`
- line 722: `cvtSampleSize`
- line 723: `cvtReadingsJson`
- line 725: `cvtCvPct`

### `lib/data/database/seeds/dummy_data_seeds.dart`

- line 1014: `pasgarSampleSize`
- line 1021: `pasgarFinalScore`
- line 1040: `pasgarSampleSize`
- line 1047: `pasgarFinalScore`
- line 1066: `pasgarSampleSize`
- line 1073: `pasgarFinalScore`
- line 1092: `pasgarSampleSize`
- line 1099: `pasgarFinalScore`
- line 1118: `pasgarSampleSize`
- line 1125: `pasgarFinalScore`
- line 1144: `pasgarSampleSize`
- line 1151: `pasgarFinalScore`
- line 1170: `pasgarSampleSize`
- line 1177: `pasgarFinalScore`
- line 1196: `pasgarSampleSize`
- line 1203: `pasgarFinalScore`
- line 1222: `pasgarSampleSize`
- line 1229: `pasgarFinalScore`
- line 1266: `sampleSize`
- line 1296: `pasgarSampleSize`
- line 1309: `pasgarFinalScore`
- line 1321: `yfbmAvgPct`
- line 1322: `yfbmCvPct`
- line 1323: `cvtSampleSize`
- line 1334: `cvtCvPct`

### `lib/data/database/seeds/troubleshooting_seeds.dart`

- line 70: `pasgar_final_score`

### `lib/data/mappers/station_sample_mapper.dart`

- line 177: `pasgarFinalScore`

### `lib/data/models/agent_intake_models.dart`

- line 337: `pasgarSampleSize`
- line 338: `pasgarReflexesCount`
- line 339: `pasgarBeakCount`
- line 340: `pasgarNavelCount`
- line 341: `pasgarBellyCount`
- line 342: `pasgarLegCount`
- line 343: `pasgarFeatherDevCount`
- line 353: `pasgarSampleSize`
- line 353: `sampleSize`
- line 359: `sampleSize`
- line 370: `pasgarReflexesCount`
- line 371: `pasgarBeakCount`
- line 371: `pasgarBeakPct`
- line 372: `pasgarNavelCount`
- line 372: `pasgarNavelPct`
- line 373: `pasgarBellyCount`
- line 373: `pasgarBellyPct`
- line 374: `pasgarLegCount`
- line 374: `pasgarLegPct`
- line 375: `pasgarFeatherDevCount`
- line 375: `pasgarFeatherDevPct`
- line 382: `sampleSize`
- line 541: `pasgarSampleSize`
- line 541: `sampleSize`
- line 544: `pasgarReflexesCount`
- line 545: `pasgarBeakCount`
- line 545: `pasgarBeakPct`
- line 546: `pasgarNavelCount`
- line 546: `pasgarNavelPct`
- line 547: `pasgarBellyCount`
- line 547: `pasgarBellyPct`
- line 548: `pasgarLegCount`
- line 548: `pasgarLegPct`
- line 549: `pasgarFeatherDevCount`
- line 549: `pasgarFeatherDevPct`
- line 554: `sampleSize`
- line 559: `sampleSize`

### `lib/data/models/audit_model.dart`

- line 24: `pasgarSampleSize`
- line 37: `pasgarFinalScore`
- line 52: `yfbmAvgPct`
- line 53: `yfbmCvPct`
- line 56: `cvtSampleSize`
- line 67: `cvtCvPct`
- line 68: `cvtReadingsJson`
- line 72: `pmSampleSize`
- line 73: `pmCollectionPoint`
- line 74: `pmOmphalitisCount`
- line 75: `pmOmphalitisSeverity`
- line 76: `pmGaseousCecaCount`
- line 77: `pmGaseousCecaSeverity`
- line 96: `pmGizzardErosionsCount`
- line 97: `pmGizzardErosionsSeverity`
- line 98: `pmAirSacCaseationsCount`
- line 99: `pmAirSacCaseationsSeverity`
- line 100: `pmUrolithiasisCount`
- line 101: `pmUrolithiasisSeverity`
- line 102: `pmNephritisCount`
- line 103: `pmNephritisSeverity`
- line 104: `pmGeneralSepticemiaCount`
- line 105: `pmGeneralSepticemiaSeverity`
- line 112: `culledChicksTotalEggSet`
- line 113: `culledChicksAnalysisJson`
- line 114: `culledChicksAffectedPct`
- line 115: `culledChicksTopCategory`
- line 116: `culledChicksTopSubtype`
- line 262: `pasgarSampleSize`
- line 275: `pasgarFinalScore`
- line 288: `yfbmAvgPct`
- line 289: `yfbmCvPct`
- line 291: `cvtSampleSize`
- line 302: `cvtCvPct`
- line 303: `cvtReadingsJson`
- line 306: `pmSampleSize`
- line 307: `pmCollectionPoint`
- line 308: `pmOmphalitisCount`
- line 309: `pmOmphalitisSeverity`
- line 310: `pmGaseousCecaCount`
- line 311: `pmGaseousCecaSeverity`
- line 330: `pmGizzardErosionsCount`
- line 331: `pmGizzardErosionsSeverity`
- line 332: `pmAirSacCaseationsCount`
- line 333: `pmAirSacCaseationsSeverity`
- line 334: `pmUrolithiasisCount`
- line 335: `pmUrolithiasisSeverity`
- line 336: `pmNephritisCount`
- line 337: `pmNephritisSeverity`
- line 338: `pmGeneralSepticemiaCount`
- line 339: `pmGeneralSepticemiaSeverity`
- line 345: `culledChicksTotalEggSet`
- line 346: `culledChicksAnalysisJson`
- line 347: `culledChicksAffectedPct`
- line 348: `culledChicksTopCategory`
- line 349: `culledChicksTopSubtype`
- line 491: `pasgarSampleSize`
- line 504: `pasgarFinalScore`
- line 517: `yfbmAvgPct`
- line 518: `yfbmCvPct`
- line 520: `cvtSampleSize`
- line 531: `cvtCvPct`
- line 532: `cvtReadingsJson`
- line 535: `pmSampleSize`
- line 536: `pmCollectionPoint`
- line 537: `pmOmphalitisCount`
- line 538: `pmOmphalitisSeverity`
- line 539: `pmGaseousCecaCount`
- line 540: `pmGaseousCecaSeverity`
- line 559: `pmGizzardErosionsCount`
- line 560: `pmGizzardErosionsSeverity`
- line 561: `pmAirSacCaseationsCount`
- line 562: `pmAirSacCaseationsSeverity`
- line 563: `pmUrolithiasisCount`
- line 564: `pmUrolithiasisSeverity`
- line 565: `pmNephritisCount`
- line 566: `pmNephritisSeverity`
- line 567: `pmGeneralSepticemiaCount`
- line 568: `pmGeneralSepticemiaSeverity`
- line 574: `culledChicksTotalEggSet`
- line 575: `culledChicksTotalEggSet`
- line 576: `culledChicksAnalysisJson`
- line 577: `culledChicksAffectedPct`
- line 578: `culledChicksTopCategory`
- line 579: `culledChicksTopSubtype`
- line 726: `pasgarSampleSize`
- line 739: `pasgarFinalScore`
- line 752: `yfbmAvgPct`
- line 753: `yfbmCvPct`
- line 755: `cvtSampleSize`
- line 766: `cvtCvPct`
- line 767: `cvtReadingsJson`
- line 770: `pmSampleSize`
- line 771: `pmCollectionPoint`
- line 772: `pmOmphalitisCount`
- line 773: `pmOmphalitisSeverity`
- line 774: `pmGaseousCecaCount`
- line 775: `pmGaseousCecaSeverity`
- line 794: `pmGizzardErosionsCount`
- line 795: `pmGizzardErosionsSeverity`
- line 796: `pmAirSacCaseationsCount`
- line 797: `pmAirSacCaseationsSeverity`
- line 798: `pmUrolithiasisCount`
- line 799: `pmUrolithiasisSeverity`
- line 800: `pmNephritisCount`
- line 801: `pmNephritisSeverity`
- line 802: `pmGeneralSepticemiaCount`
- line 803: `pmGeneralSepticemiaSeverity`
- line 809: `culledChicksTotalEggSet`
- line 810: `culledChicksAnalysisJson`
- line 811: `culledChicksAffectedPct`
- line 812: `culledChicksTopCategory`
- line 813: `culledChicksTopSubtype`

### `lib/data/models/breeder_alert_models.dart`

- line 27: `cvPct`
- line 27: `uniformityPct`
- line 36: `uniformityPct`
- line 36: `uniformity_pct`
- line 37: `cvPct`
- line 37: `cv_pct`
- line 43: `uniformityPct`
- line 44: `cvPct`

### `lib/data/models/breeder_weighing_session_model.dart`

- line 44: `sampleSize`
- line 64: `sampleSize`
- line 87: `sampleSize`
- line 111: `sampleSize`
- line 129: `sampleSize`
- line 150: `sampleSize`

### `lib/data/models/lab_analysis_models.dart`

- line 215: `cvPct`
- line 255: `cvPct`
- line 297: `cvPct`
- line 342: `cvPct`
- line 384: `cvPct`
- line 434: `cvPct`
- line 774: `cvPct`

### `lib/data/models/panel_sample_model.dart`

- line 286: `sampleSize`
- line 314: `sampleSize`
- line 341: `sampleSize`
- line 370: `sampleSize`

### `lib/data/models/panel_sample_schema.dart`

- line 148: `pasgarSampleSize`
- line 149: `pasgarReflexesCount`
- line 150: `pasgarBeakCount`
- line 151: `pasgarNavelCount`
- line 152: `pasgarBellyCount`
- line 153: `pasgarLegCount`
- line 154: `pasgarFeatherDevCount`
- line 155: `pasgarReflexesPct`
- line 156: `pasgarBeakPct`
- line 157: `pasgarNavelPct`
- line 158: `pasgarBellyPct`
- line 159: `pasgarLegPct`
- line 160: `pasgarFeatherDevPct`
- line 161: `pasgarFinalScore`
- line 163: `yfbmEntriesJson`
- line 164: `yfbmEntryCount`
- line 165: `yfbmAvgPct`
- line 166: `yfbmCvPct`
- line 167: `cvtReadingsJson`
- line 169: `cvtSampleSize`
- line 179: `cvtAvgTemp`
- line 180: `cvtCvPct`
- line 181: `pmSampleSize`
- line 182: `pmCollectionPoint`
- line 183: `pmOmphalitisCount`
- line 184: `pmOmphalitisSeverity`
- line 185: `pmGaseousCecaCount`
- line 186: `pmGaseousCecaSeverity`
- line 187: `pmGizzardErosionsCount`
- line 188: `pmGizzardErosionsSeverity`
- line 189: `pmAirSacCaseationsCount`
- line 190: `pmAirSacCaseationsSeverity`
- line 191: `pmUrolithiasisCount`
- line 192: `pmUrolithiasisSeverity`
- line 193: `pmNephritisCount`
- line 194: `pmNephritisSeverity`
- line 195: `pmGeneralSepticemiaCount`
- line 196: `pmGeneralSepticemiaSeverity`
- line 201: `culledChicksTotalEggSet`
- line 202: `culledChicksAnalysisJson`
- line 203: `culledChicksAffectedPct`
- line 204: `culledChicksTopCategory`
- line 205: `culledChicksTopSubtype`
- line 214: `weightsJson`
- line 215: `sampleSize`
- line 216: `avgWeight`
- line 217: `uniformityPct`
- line 218: `cvPct`
- line 356: `cvtReadingsJson`
- line 358: `cvtSampleSize`
- line 360: `cvtCvPct`

### `lib/data/repositories/breeder_weighing_session_repository.dart`

- line 53: `sampleSize`
- line 65: `sampleSize`

### `lib/data/repositories/egg_grading_repository.dart`

- line 30: `sampleSize`
- line 89: `sampleSize`
- line 135: `sampleSize`
- line 137: `sampleSize`

### `lib/data/repositories/panel_dashboard_repository.dart`

- line 354: `weightsJson`
- line 371: `avgWeight`
- line 372: `uniformityPct`
- line 373: `cvPct`
- line 381: `pasgarFinalScore`
- line 387: `pasgarFinalScore`
- line 388: `pasgarReflexesPct`
- line 389: `pasgarBeakPct`
- line 390: `pasgarNavelPct`
- line 391: `pasgarBellyPct`
- line 392: `pasgarLegPct`
- line 393: `pasgarFeatherDevPct`
- line 399: `cvtAvgTemp`
- line 404: `cvtAvgTemp`
- line 405: `cvPct`
- line 405: `cvtCvPct`
- line 415: `yfbmAvgPct`
- line 423: `yfbmAvgPct`
- line 424: `cvPct`
- line 424: `yfbmCvPct`
- line 440: `culledChicksTotalEggSet`
- line 442: `culledChicksAnalysisJson`
- line 531: `uniformityPct`
- line 532: `cvPct`
- line 605: `cvtCvPct`
- line 607: `cvtReadingsJson`
- line 687: `avgWeight`
- line 688: `avgWeight`
- line 689: `avgWeight`
- line 692: `avgWeight`
- line 693: `uniformityPct`
- line 698: `cvPct`

### `lib/data/repositories/panel_sample_repository.dart`

- line 845: `sampleSize`
- line 871: `chicks.legacy_combined`
- line 875: `chicks.legacy_combined`
- line 1126: `chicks.legacy_combined`
- line 1164: `chicks.legacy_combined`
- line 1266: `chicks.legacy_combined`

### `lib/data/services/panel_aggregate_deriver.dart`

- line 71: `cvtReadingsJson`
- line 72: `cvtAvgTemp`
- line 73: `cvtCvPct`
- line 75: `cvtSampleSize`
- line 80: `weightsJson`
- line 81: `sampleSize`
- line 82: `avgWeight`
- line 83: `uniformityPct`
- line 84: `cvPct`
- line 99: `cvtReadingsJson`
- line 101: `cvtCvPct`
- line 103: `cvtSampleSize`
- line 167: `pasgarSampleSize`
- line 170: `pasgarReflexesCount`
- line 171: `pasgarBeakCount`
- line 172: `pasgarNavelCount`
- line 173: `pasgarBellyCount`
- line 174: `pasgarLegCount`
- line 175: `pasgarFeatherDevCount`
- line 178: `pasgarReflexesPct`
- line 179: `pasgarBeakPct`
- line 180: `pasgarNavelPct`
- line 181: `pasgarBellyPct`
- line 182: `pasgarLegPct`
- line 183: `pasgarFeatherDevPct`
- line 193: `pasgarFinalScore`

### `lib/features/audits/logic/audit_meaningful_data.dart`

- line 137: `yfbmAvgPct`
- line 138: `yfbmCvPct`
- line 139: `cvtSampleSize`
- line 150: `cvtCvPct`
- line 151: `cvtReadingsJson`
- line 154: `culledChicksTotalEggSet`
- line 155: `culledChicksAnalysisJson`
- line 156: `culledChicksAffectedPct`
- line 157: `culledChicksTopCategory`
- line 158: `culledChicksTopSubtype`
- line 166: `yfbmAvgPct`
- line 167: `yfbmCvPct`
- line 168: `cvtSampleSize`
- line 179: `cvtCvPct`
- line 180: `cvtReadingsJson`
- line 183: `culledChicksTotalEggSet`
- line 184: `culledChicksAnalysisJson`
- line 185: `culledChicksAffectedPct`
- line 186: `culledChicksTopCategory`
- line 187: `culledChicksTopSubtype`
- line 192: `pasgarSampleSize`
- line 205: `pasgarFinalScore`
- line 226: `pmSampleSize`
- line 227: `pmCollectionPoint`
- line 228: `pmOmphalitisCount`
- line 229: `pmOmphalitisSeverity`
- line 230: `pmGaseousCecaCount`
- line 231: `pmGaseousCecaSeverity`
- line 232: `pmGizzardErosionsCount`
- line 233: `pmGizzardErosionsSeverity`
- line 234: `pmAirSacCaseationsCount`
- line 235: `pmAirSacCaseationsSeverity`
- line 236: `pmUrolithiasisCount`
- line 237: `pmUrolithiasisSeverity`
- line 238: `pmNephritisCount`
- line 239: `pmNephritisSeverity`
- line 240: `pmGeneralSepticemiaCount`
- line 241: `pmGeneralSepticemiaSeverity`
- line 561: `weightsJson`
- line 562: `sampleSize`
- line 563: `avgWeight`
- line 564: `uniformityPct`
- line 565: `cvPct`

### `lib/features/audits/logic/egg_station_reconstruction.dart`

- line 192: `sampleSize`
- line 484: `weightsJson`
- line 485: `avgWeight`
- line 486: `uniformityPct`
- line 487: `cvPct`

### `lib/features/audits/logic/panel_row_to_draft.dart`

- line 74: `pasgarSampleSize`
- line 75: `pasgarReflexesCount`
- line 76: `pasgarBeakCount`
- line 77: `pasgarNavelCount`
- line 78: `pasgarBellyCount`
- line 79: `pasgarLegCount`
- line 80: `pasgarFeatherDevCount`
- line 81: `pasgarFinalScore`
- line 83: `yfbmEntriesJson`
- line 84: `yfbmAvgPct`
- line 85: `yfbmCvPct`
- line 86: `cvtReadingsJson`
- line 88: `cvtSampleSize`
- line 98: `cvtAvgTemp`
- line 99: `cvtCvPct`
- line 100: `pmSampleSize`
- line 101: `pmCollectionPoint`
- line 102: `pmOmphalitisCount`
- line 103: `pmOmphalitisSeverity`
- line 104: `pmGaseousCecaCount`
- line 105: `pmGaseousCecaSeverity`
- line 124: `pmGizzardErosionsCount`
- line 125: `pmGizzardErosionsSeverity`
- line 126: `pmAirSacCaseationsCount`
- line 127: `pmAirSacCaseationsSeverity`
- line 128: `pmUrolithiasisCount`
- line 129: `pmUrolithiasisSeverity`
- line 130: `pmNephritisCount`
- line 131: `pmNephritisSeverity`
- line 132: `pmGeneralSepticemiaCount`
- line 133: `pmGeneralSepticemiaSeverity`
- line 138: `culledChicksTotalEggSet`
- line 139: `culledChicksAnalysisJson`
- line 140: `culledChicksAffectedPct`
- line 141: `culledChicksTopCategory`
- line 142: `culledChicksTopSubtype`
- line 145: `weightsJson`
- line 146: `sampleSize`
- line 147: `avgWeight`
- line 148: `uniformityPct`
- line 149: `cvPct`
- line 204: `cvtReadingsJson`
- line 207: `cvtCvPct`

### `lib/features/audits/logic/panel_value_builders.dart`

- line 95: `cvtReadingsJson`
- line 97: `cvtSampleSize`
- line 99: `cvtCvPct`
- line 202: `sampleSize`
- line 218: `sampleSize`
- line 230: `pasgarSampleSize`
- line 231: `culledChicksTotalEggSet`
- line 232: `culledChicksTotalEggSet`
- line 233: `culledChicksAnalysisJson`
- line 237: `culledChicksAnalysisJson`
- line 238: `culledChicksTotalEggSet`
- line 241: `pasgarSampleSize`
- line 242: `pasgarReflexesCount`
- line 243: `pasgarBeakCount`
- line 244: `pasgarNavelCount`
- line 245: `pasgarBellyCount`
- line 246: `pasgarLegCount`
- line 247: `pasgarFeatherDevCount`
- line 248: `pasgarReflexesPct`
- line 249: `pasgarBeakPct`
- line 250: `pasgarNavelPct`
- line 251: `pasgarBellyPct`
- line 252: `pasgarLegPct`
- line 253: `pasgarFeatherDevPct`
- line 254: `pasgarFinalScore`
- line 256: `yfbmEntriesJson`
- line 257: `yfbmEntryCount`
- line 258: `yfbmAvgPct`
- line 259: `yfbmCvPct`
- line 260: `cvtReadingsJson`
- line 262: `cvtSampleSize`
- line 272: `cvtAvgTemp`
- line 273: `cvtCvPct`
- line 275: `culledChicksTotalEggSet`
- line 276: `culledChicksAnalysisJson`
- line 277: `culledChicksAffectedPct`
- line 278: `culledChicksTopCategory`
- line 279: `culledChicksTopSubtype`
- line 284: `pasgarSampleSize`
- line 285: `pasgarReflexesCount`
- line 286: `pasgarBeakCount`
- line 287: `pasgarNavelCount`
- line 288: `pasgarBellyCount`
- line 289: `pasgarLegCount`
- line 290: `pasgarFeatherDevCount`
- line 291: `pasgarReflexesPct`
- line 292: `pasgarBeakPct`
- line 293: `pasgarNavelPct`
- line 294: `pasgarBellyPct`
- line 295: `pasgarLegPct`
- line 296: `pasgarFeatherDevPct`
- line 297: `pasgarFinalScore`
- line 298: `yfbmEntriesJson`
- line 299: `yfbmEntryCount`
- line 300: `yfbmAvgPct`
- line 301: `yfbmCvPct`
- line 302: `cvtReadingsJson`
- line 303: `cvtSampleSize`
- line 304: `cvtAvgTemp`
- line 305: `cvtCvPct`
- line 306: `pmSampleSize`
- line 307: `pmCollectionPoint`
- line 308: `pmOmphalitisCount`
- line 309: `pmOmphalitisSeverity`
- line 310: `pmGaseousCecaCount`
- line 311: `pmGaseousCecaSeverity`
- line 312: `pmGizzardErosionsCount`
- line 313: `pmGizzardErosionsSeverity`
- line 314: `pmAirSacCaseationsCount`
- line 315: `pmAirSacCaseationsSeverity`
- line 316: `pmUrolithiasisCount`
- line 317: `pmUrolithiasisSeverity`
- line 318: `pmNephritisCount`
- line 319: `pmNephritisSeverity`
- line 320: `pmGeneralSepticemiaCount`
- line 321: `pmGeneralSepticemiaSeverity`
- line 322: `culledChicksTotalEggSet`
- line 323: `culledChicksAnalysisJson`
- line 324: `culledChicksAffectedPct`
- line 325: `culledChicksTopCategory`
- line 326: `culledChicksTopSubtype`
- line 336: `weightsJson`
- line 337: `sampleSize`
- line 338: `avgWeight`
- line 339: `uniformityPct`
- line 340: `cvPct`
- line 397: `weightsJson`
- line 398: `sampleSize`
- line 399: `avgWeight`
- line 400: `uniformityPct`
- line 401: `cvPct`
- line 409: `weightsJson`
- line 410: `sampleSize`
- line 411: `avgWeight`
- line 412: `uniformityPct`
- line 413: `cvPct`
- line 421: `pmSampleSize`
- line 422: `pmCollectionPoint`
- line 423: `pmOmphalitisCount`
- line 424: `pmOmphalitisSeverity`
- line 425: `pmGaseousCecaCount`
- line 426: `pmGaseousCecaSeverity`
- line 427: `pmGizzardErosionsCount`
- line 428: `pmGizzardErosionsSeverity`
- line 429: `pmAirSacCaseationsCount`
- line 430: `pmAirSacCaseationsSeverity`
- line 431: `pmUrolithiasisCount`
- line 432: `pmUrolithiasisSeverity`
- line 433: `pmNephritisCount`
- line 434: `pmNephritisSeverity`
- line 435: `pmGeneralSepticemiaCount`
- line 436: `pmGeneralSepticemiaSeverity`

### `lib/features/audits/models/egg_grading.dart`

- line 185: `sampleSize`
- line 190: `sampleSize`
- line 194: `sampleSize`
- line 217: `sampleSize`
- line 219: `sampleSize`
- line 240: `sampleSize`
- line 245: `sampleSize`
- line 256: `sampleSize`
- line 278: `sampleSize`
- line 292: `sampleSize`
- line 297: `sampleSize`
- line 299: `sampleSize`
- line 306: `sampleSize`

### `lib/features/audits/providers/audit_provider.dart`

- line 429: `sampleSize`
- line 437: `sampleSize`
- line 982: `sampleSize`
- line 986: `sampleSize`
- line 1521: `weightsJson`
- line 1522: `avgWeight`
- line 1523: `uniformityPct`
- line 1524: `cvPct`
- line 1531: `weightsJson`
- line 1532: `weightsJson`
- line 1533: `avgWeight`
- line 1534: `uniformityPct`
- line 1535: `cvPct`
- line 1544: `weightsJson`
- line 1545: `weightsJson`
- line 1546: `avgWeight`
- line 1547: `uniformityPct`
- line 1548: `cvPct`
- line 1843: `weightsJson`
- line 1845: `weightsJson`
- line 2502: `weightsJson`
- line 2503: `weightsJson`
- line 2540: `pasgarFinalScore`
- line 2541: `pasgarFinalScore`
- line 2545: `pasgarFinalScore`

### `lib/features/audits/screens/chick_quality_screen.dart`

- line 489: `weightsJson`
- line 504: `weightsJson`
- line 505: `avgWeight`
- line 506: `uniformityPct`
- line 507: `cvPct`

### `lib/features/audits/screens/egg_storage_screen.dart`

- line 281: `weightsJson`
- line 282: `weightsJson`
- line 284: `weightsJson`
- line 1589: `sampleSize`
- line 2028: `sampleSize`
- line 2536: `sampleSize`
- line 2776: `sampleSize`
- line 2784: `sampleSize`

### `lib/features/audits/services/audit_panel_save_coordinator.dart`

- line 212: `sampleSize`
- line 226: `sampleSize`
- line 475: `sampleSize`
- line 1003: `sampleSize`
- line 1019: `weightsJson`
- line 1020: `sampleSize`
- line 1021: `avgWeight`
- line 1022: `uniformityPct`
- line 1023: `cvPct`
- line 1185: `pasgarSampleSize`
- line 1186: `cvtSampleSize`
- line 1187: `pmSampleSize`
- line 1188: `culledChicksTotalEggSet`

### `lib/features/audits/widgets/tabs/culled_chicks_analysis_tab.dart`

- line 36: `culledChicksTotalEggSet`
- line 37: `culledChicksTotalEggSet`
- line 43: `culledChicksAnalysisJson`
- line 110: `culledChicksTotalEggSet`
- line 146: `culledChicksTotalEggSet`
- line 147: `culledChicksAnalysisJson`
- line 148: `culledChicksAffectedPct`
- line 149: `culledChicksTopCategory`
- line 150: `culledChicksTopSubtype`

### `lib/features/audits/widgets/tabs/cvt_tab.dart`

- line 100: `cvtReadingsJson`
- line 199: `cvtReadingsJson`
- line 204: `cvtCvPct`
- line 205: `cvtSampleSize`

### `lib/features/audits/widgets/tabs/egg_grading_section.dart`

- line 67: `sampleSize`
- line 176: `sampleSize`

### `lib/features/audits/widgets/tabs/pasgar_tab.dart`

- line 46: `pasgarSampleSize`
- line 66: `pasgarSampleSize`
- line 67: `pasgarSampleSize`
- line 76: `sampleSize`
- line 84: `sampleSize`
- line 91: `sampleSize`
- line 97: `sampleSize`
- line 292: `pasgarSampleSize`
- line 403: `sampleSize`
- line 407: `sampleSize`
- line 621: `sampleSize`
- line 623: `sampleSize`
- line 641: `sampleSize`
- line 654: `sampleSize`
- line 660: `pasgarFinalScore`
- line 661: `sampleSize`
- line 666: `sampleSize`
- line 667: `sampleSize`
- line 669: `sampleSize`
- line 673: `sampleSize`
- line 674: `sampleSize`
- line 676: `sampleSize`

### `lib/features/audits/widgets/tabs/pm_necropsy_tab.dart`

- line 42: `pmSampleSize`
- line 45: `pmCollectionPoint`
- line 165: `pmOmphalitisCount`
- line 166: `pmOmphalitisSeverity`
- line 171: `pmGaseousCecaCount`
- line 172: `pmGaseousCecaSeverity`
- line 177: `pmAirSacCaseationsCount`
- line 178: `pmAirSacCaseationsSeverity`
- line 183: `pmUrolithiasisCount`
- line 184: `pmUrolithiasisSeverity`
- line 189: `pmNephritisCount`
- line 190: `pmNephritisSeverity`
- line 195: `pmGeneralSepticemiaCount`
- line 196: `pmGeneralSepticemiaSeverity`
- line 201: `pmGizzardErosionsCount`
- line 202: `pmGizzardErosionsSeverity`

### `lib/features/audits/widgets/tabs/yfbm_tab.dart`

- line 98: `yfbmAvgPct`
- line 99: `yfbmCvPct`

### `lib/features/breeder/screens/breeder_weighing_session_entry_screen.dart`

- line 87: `sampleSize`
- line 143: `sampleSize`
- line 153: `sampleSize`
- line 177: `sampleSize`
- line 186: `sampleSize`

### `lib/features/breeder/screens/breeder_weighing_session_list_screen.dart`

- line 125: `sampleSize`

### `lib/features/customers/screens/audit_detail_screen.dart`

- line 238: `pasgarSampleSize`
- line 239: `pasgarFinalScore`
- line 260: `yfbmAvgPct`
- line 261: `yfbmCvPct`
- line 271: `cvtCvPct`

### `lib/features/customers/screens/visit_detail_screen.dart`

- line 452: `pasgarFinalScore`
- line 454: `pasgarFinalScore`

### `lib/features/dashboard/models/chick_quality_models.dart`

- line 6: `uniformityPct`
- line 7: `cvPct`
- line 12: `uniformityPct`
- line 13: `cvPct`
- line 20: `uniformityPct`
- line 21: `cvPct`
- line 101: `cvPct`
- line 103: `cvPct`
- line 108: `cvPct`
- line 116: `cvPct`
- line 118: `cvPct`
- line 124: `cvPct`

### `lib/features/dashboard/models/egg_storage_models.dart`

- line 96: `uniformityPct`
- line 97: `cvPct`
- line 119: `uniformityPct`
- line 120: `cvPct`
- line 144: `uniformityPct`
- line 145: `cvPct`
- line 272: `cvtCvPct`
- line 293: `cvtCvPct`
- line 317: `cvtReadingsJson`
- line 320: `cvtCvPct`

### `lib/features/dashboard/models/lab_analysis_trend_models.dart`

- line 8: `cvPct`
- line 16: `cvPct`
- line 125: `cvPct`
- line 139: `cvPct`
- line 155: `cvPct`

### `lib/features/dashboard/models/visit_session_summary.dart`

- line 299: `pasgarFinalScore`
- line 342: `pasgarFinalScore`
- line 345: `cvPct`
- line 466: `pmOmphalitisCount`
- line 467: `pmGaseousCecaCount`
- line 477: `pmGizzardErosionsCount`
- line 478: `pmAirSacCaseationsCount`
- line 479: `pmUrolithiasisCount`
- line 480: `pmNephritisCount`
- line 481: `pmGeneralSepticemiaCount`
- line 501: `pmOmphalitisCount`
- line 502: `pmGaseousCecaCount`
- line 512: `pmGizzardErosionsCount`
- line 513: `pmAirSacCaseationsCount`
- line 514: `pmUrolithiasisCount`
- line 515: `pmNephritisCount`
- line 516: `pmGeneralSepticemiaCount`

### `lib/features/dashboard/scope/scope_config.dart`

- line 327: `pasgarFinalScore`
- line 328: `pasgarSampleSize`
- line 334: `pasgarReflexesPct`
- line 335: `pasgarReflexesCount`
- line 336: `pasgarSampleSize`
- line 341: `pasgarBeakPct`
- line 342: `pasgarBeakCount`
- line 343: `pasgarSampleSize`
- line 349: `pasgarNavelPct`
- line 350: `pasgarNavelCount`
- line 351: `pasgarSampleSize`
- line 357: `pasgarBellyPct`
- line 358: `pasgarBellyCount`
- line 359: `pasgarSampleSize`
- line 365: `pasgarLegPct`
- line 366: `pasgarLegCount`
- line 367: `pasgarSampleSize`
- line 373: `pasgarFeatherDevPct`
- line 374: `pasgarFeatherDevCount`
- line 375: `pasgarSampleSize`
- line 380: `cvtAvgTemp`
- line 381: `cvtSampleSize`
- line 386: `cvtCvPct`
- line 387: `cvtSampleSize`
- line 393: `yfbmAvgPct`
- line 394: `yfbmEntryCount`
- line 407: `sampleSize`
- line 410: `avgWeight`
- line 411: `sampleSize`
- line 416: `uniformityPct`
- line 417: `sampleSize`
- line 425: `cvPct`
- line 426: `sampleSize`
- line 654: `cvtSampleSize`
- line 659: `cvtCvPct`
- line 660: `cvtSampleSize`

### `lib/features/dashboard/scope/scope_station_items.dart`

- line 67: `pasgarFinalScore`
- line 68: `pasgarReflexesPct`
- line 69: `pasgarBeakPct`
- line 70: `pasgarNavelPct`
- line 71: `pasgarBellyPct`
- line 72: `pasgarLegPct`
- line 73: `pasgarFeatherDevPct`
- line 79: `cvtAvgTemp`
- line 79: `cvtCvPct`
- line 84: `yfbmAvgPct`
- line 124: `cvtCvPct`

### `lib/features/dashboard/widgets/lab_analysis_trend_panel.dart`

- line 786: `cvPct`
- line 788: `cvPct`

### `lib/features/dashboard/widgets/scope/station_kpi_strip.dart`

- line 26: `pasgarFinalScore`

### `lib/features/dashboard/widgets/sections/chick_quality_section.dart`

- line 101: `uniformityPct`
- line 104: `cvPct`
- line 106: `cvPct`
- line 142: `pasgar_final_score`
- line 354: `cvPct`
- line 356: `cvPct`
- line 402: `cvPct`

### `lib/features/dashboard/widgets/sections/egg_quality_section.dart`

- line 198: `cvPct`
- line 200: `uniformityPct`
- line 201: `uniformityPct`
- line 219: `uniformityPct`
- line 221: `uniformityPct`
- line 228: `cvPct`

### `lib/features/dashboard/widgets/sections/egg_storage_section.dart`

- line 834: `uniformityPct`
- line 841: `uniformityPct`
- line 844: `cvPct`
- line 846: `cvPct`
- line 880: `uniformityPct`

### `lib/features/dashboard/widgets/sections/hatcher_optimizing_section.dart`

- line 94: `cvtCvPct`

### `lib/features/lab_analysis/providers/lab_analysis_provider.dart`

- line 145: `cvPct`
- line 185: `cvPct`

### `lib/features/lab_analysis/screens/lab_analysis_screen.dart`

- line 591: `cvPct`
- line 1799: `cvPct`

### `lib/features/settings/providers/settings_provider.dart`

- line 46: `pasgarSampleSize`

### `lib/features/settings/screens/settings_screen.dart`

- line 158: `pasgarSampleSize`

### `lib/services/breeder/breeder_alert_revision_hook.dart`

- line 11: `cv_pct`
- line 11: `uniformity_pct`
- line 53: `uniformityPct`
- line 54: `cvPct`
- line 91: `uniformityPct`
- line 93: `cvPct`

### `lib/services/breeder/breeder_weighing_service.dart`

- line 77: `uniformityPct`
- line 84: `cvPct`
- line 89: `uniformityPct`
- line 90: `cvPct`
- line 96: `uniformityPct`
- line 97: `cvPct`
- line 174: `uniformityPct`
- line 175: `cvPct`
- line 262: `uniformityPct`
- line 263: `cvPct`
- line 290: `sampleSize`
- line 294: `sampleSize`
- line 295: `sampleSize`
- line 312: `sampleSize`

### `supabase/functions/app-hatchery-agent/evals/comparison_scenarios.ts`

- line 909: `pasgarSampleSize`
- line 910: `pasgarFinalScore`
- line 993: `pasgarFinalScore`

### `supabase/functions/telegram-hatchery-agent/agent_metrics.ts`

- line 133: `sampleSize`
- line 136: `sampleSize`
- line 138: `sampleSize`
- line 141: `sampleSize`

### `supabase/functions/telegram-hatchery-agent/agent_read_tools.ts`

- line 209: `chicks.legacy_combined`
- line 824: `chicks.legacy_combined`
- line 1060: `chicks.legacy_combined`
- line 1164: `pasgarFinalScore`
- line 1167: `pasgarSampleSize`
- line 1175: `pasgarSampleSize`

### `supabase/functions/telegram-hatchery-agent/agent_station_adapter.ts`

- line 376: `yfbm_entry_count`
- line 382: `yfbm_cv_pct`

### `supabase/functions/telegram-hatchery-agent/pasgar_intake_schema.ts`

- line 10: `pasgarSampleSize`
- line 11: `pasgarReflexesCount`
- line 12: `pasgarBeakCount`
- line 13: `pasgarNavelCount`
- line 14: `pasgarBellyCount`
- line 15: `pasgarLegCount`
- line 16: `pasgarFeatherDevCount`
- line 36: `pasgarSampleSize`
- line 58: `sampleSize`
- line 67: `pasgarSampleSize`
- line 68: `pasgarSampleSize`
- line 76: `pasgarReflexesCount`
- line 77: `pasgarReflexesCount`
- line 85: `pasgarBeakCount`
- line 86: `pasgarBeakCount`
- line 94: `pasgarNavelCount`
- line 95: `pasgarNavelCount`
- line 103: `pasgarBellyCount`
- line 104: `pasgarBellyCount`
- line 112: `pasgarLegCount`
- line 113: `pasgarLegCount`
- line 121: `pasgarFeatherDevCount`
- line 122: `pasgarFeatherDevCount`
- line 156: `pasgarSampleSize`
- line 193: `pasgarSampleSize`
- line 193: `sampleSize`
- line 194: `sampleSize`
- line 198: `sampleSize`
- line 199: `sampleSize`
- line 230: `pasgarSampleSize`
- line 230: `sampleSize`
- line 232: `pasgarSampleSize`
- line 233: `sampleSize`
- line 245: `sampleSize`
- line 249: `pasgarReflexesCount`
- line 250: `pasgarBeakCount`
- line 251: `pasgarNavelCount`
- line 252: `pasgarBellyCount`
- line 253: `pasgarLegCount`
- line 255: `sampleSize`
- line 260: `sampleSize`
- line 280: `sampleSize`
- line 281: `sampleSize`
