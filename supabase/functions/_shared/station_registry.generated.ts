// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: tool/agent_schema/station_registry.json
// deno-fmt-ignore-file

export interface AgentStationSchema {
  readonly schemaKey: string
  readonly version: number
  readonly sectorKeys: readonly string[]
  readonly stationKey: string
  readonly moduleKey: string
  readonly names: Readonly<Record<'en' | 'ar', string>>
  readonly aliases: Readonly<Record<'en' | 'ar', readonly string[]>>
  readonly allowedLayers: readonly string[]
  readonly fields: readonly Record<string, unknown>[]
  readonly calculations: readonly Record<string, unknown>[]
  readonly completion: Readonly<{ requiredFieldKeys: readonly string[] }>
  readonly persistence: readonly Readonly<{
    localTable: string
    remoteTable: string
  }>[]
  readonly read: Readonly<{
    dimensions: readonly string[]
    measures: readonly string[]
  }>
  readonly warnings: readonly Record<string, unknown>[]
}

export const agentStationRegistry = {
  "registryVersion": 1,
  "qualityClassification": {
    "statusOrder": [
      "OK",
      "FLAG",
      "WARN",
      "BLOCK"
    ],
    "missing": {
      "tier": "FLAG",
      "code": "missing_required"
    },
    "missingRawEvidence": {
      "tier": "FLAG",
      "code": "missing_raw_evidence"
    },
    "derivedCacheMismatch": {
      "tier": "FLAG",
      "code": "derived_cache_mismatch"
    },
    "legacyUnclassified": {
      "tier": "FLAG",
      "code": "legacy_quality_unclassified"
    },
    "structural": {
      "domainMismatch": {
        "tier": "BLOCK",
        "code": "domain_mismatch"
      },
      "schemaVersionMismatch": {
        "tier": "BLOCK",
        "code": "schema_version_mismatch"
      },
      "scopeNotAllowed": {
        "tier": "BLOCK",
        "code": "scope_not_allowed"
      },
      "malformedIdentity": {
        "tier": "BLOCK",
        "code": "malformed_identity"
      }
    },
    "validationIssueTiers": {
      "unknown_field": "WARN",
      "invalid_type": "BLOCK",
      "zero_not_allowed": "WARN",
      "below_minimum": "WARN",
      "above_maximum": "WARN",
      "above_dynamic_maximum": "WARN",
      "too_short": "WARN",
      "too_few_items": "WARN",
      "too_many_items": "WARN",
      "item_out_of_range": "WARN",
      "item_required": "WARN",
      "unknown_item_property": "WARN",
      "invalid_item_type": "BLOCK",
      "item_below_minimum": "WARN",
      "item_above_maximum": "WARN",
      "invalid_item_choice": "WARN",
      "invalid_choice": "WARN"
    },
    "parityVectors": [
      {
        "schemaKey": "chicks.pasgar",
        "schemaVersion": 1,
        "values": {
          "pasgarSampleSize": 20,
          "pasgarReflexesCount": 1,
          "pasgarReflexesPct": 5.0
        },
        "context": {
          "domain": "chicks.pasgar",
          "schemaVersion": 1,
          "scopeType": "pool",
          "scopeKey": "{}",
          "sampleKey": "stable-key"
        },
        "expectedStatus": "FLAG",
        "expectedFlags": [
          {
            "tier": "FLAG",
            "schemaKey": "chicks.pasgar",
            "fieldKey": "pasgarBeakCount",
            "code": "missing_required"
          },
          {
            "tier": "FLAG",
            "schemaKey": "chicks.pasgar",
            "fieldKey": "pasgarBellyCount",
            "code": "missing_required"
          },
          {
            "tier": "FLAG",
            "schemaKey": "chicks.pasgar",
            "fieldKey": "pasgarFeatherDevCount",
            "code": "missing_required"
          },
          {
            "tier": "FLAG",
            "schemaKey": "chicks.pasgar",
            "fieldKey": "pasgarLegCount",
            "code": "missing_required"
          },
          {
            "tier": "FLAG",
            "schemaKey": "chicks.pasgar",
            "fieldKey": "pasgarNavelCount",
            "code": "missing_required"
          }
        ]
      },
      {
        "schemaKey": "chicks.weights",
        "schemaVersion": 1,
        "values": {
          "weightsJson": [
            40
          ]
        },
        "context": {
          "domain": "chicks.weights",
          "schemaVersion": 1,
          "scopeType": "setter_hatcher",
          "scopeKey": "{\"hatcher\":\"H1\",\"setter\":\"S1\"}",
          "sampleKey": "stable-key"
        },
        "expectedStatus": "BLOCK",
        "expectedFlags": [
          {
            "tier": "BLOCK",
            "schemaKey": "chicks.weights",
            "fieldKey": "$sample",
            "code": "scope_not_allowed"
          }
        ]
      }
    ]
  },
  "calculationParityVectors": {
    "percentOf": [
      {
        "count": 3,
        "total": 40,
        "expected": 7.5
      }
    ],
    "cvPercent": [
      {
        "values": [
          10,
          12,
          14
        ],
        "sample": true,
        "expected": 16.7
      }
    ],
    "uniformityPercent": [
      {
        "values": [
          8,
          9,
          10,
          11,
          12
        ],
        "minimum": 9,
        "maximum": 11,
        "expected": 60.0
      }
    ],
    "pasgarScore": [
      {
        "sampleSize": 40,
        "defectCounts": [
          2,
          1,
          3,
          1,
          2,
          3
        ],
        "expected": 9.8
      }
    ],
    "fertility": [
      {
        "fertile": 90,
        "clear": 10,
        "expected": 90.0
      }
    ],
    "hatchability": [
      {
        "hatched": 85,
        "total": 100,
        "expected": 85.0
      }
    ],
    "hof": [
      {
        "hatchability": 85,
        "fertility": 90,
        "expected": 94.4
      }
    ]
  },
  "stations": [
    {
      "schemaKey": "chicks.pasgar",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "pasgar",
      "names": {
        "en": "Chick Quality — Pasgar",
        "ar": "جودة الكتاكيت — باسجار"
      },
      "aliases": {
        "en": [
          "pasgar",
          "chick quality score"
        ],
        "ar": [
          "باسجار",
          "جودة الكتكوت",
          "جودة الكتاكيت"
        ]
      },
      "allowedLayers": [
        "pool",
        "setter_hatcher"
      ],
      "photoEvidence": {
        "pasgarReflexesPhoto": "pasgarReflexesCount",
        "pasgarBeakPhoto": "pasgarBeakCount",
        "pasgarNavelPhoto": "pasgarNavelCount",
        "pasgarBellyPhoto": "pasgarBellyCount",
        "pasgarLegPhoto": "pasgarLegCount",
        "pasgarFeatherDevPhoto": "pasgarFeatherDevCount"
      },
      "fields": [
        {
          "fieldKey": "pasgarSampleSize",
          "names": {
            "en": "Sample size",
            "ar": "حجم العينة"
          },
          "aliases": {
            "en": [
              "sample",
              "sample number",
              "sample size"
            ],
            "ar": [
              "العينة",
              "عدد العينة",
              "حجم العينة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 500
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarSampleSize"
          },
          "persistence": {
            "localColumn": "pasgarSampleSize",
            "remoteColumn": "pasgar_sample_size"
          }
        },
        {
          "fieldKey": "pasgarReflexesCount",
          "names": {
            "en": "Reflexes",
            "ar": "ردود الأفعال"
          },
          "aliases": {
            "en": [
              "reflex",
              "reflexes"
            ],
            "ar": [
              "رد الفعل",
              "ردود الافعال",
              "ردود الأفعال"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarReflexesCount"
          },
          "persistence": {
            "localColumn": "pasgarReflexesCount",
            "remoteColumn": "pasgar_reflexes_count"
          }
        },
        {
          "fieldKey": "pasgarBeakCount",
          "names": {
            "en": "Beak",
            "ar": "المنقار"
          },
          "aliases": {
            "en": [
              "beak",
              "peak"
            ],
            "ar": [
              "المنقار",
              "منقار"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarBeakCount"
          },
          "persistence": {
            "localColumn": "pasgarBeakCount",
            "remoteColumn": "pasgar_beak_count"
          }
        },
        {
          "fieldKey": "pasgarNavelCount",
          "names": {
            "en": "Navel",
            "ar": "السرة"
          },
          "aliases": {
            "en": [
              "navel"
            ],
            "ar": [
              "السرة",
              "سره",
              "سرة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarNavelCount"
          },
          "persistence": {
            "localColumn": "pasgarNavelCount",
            "remoteColumn": "pasgar_navel_count"
          }
        },
        {
          "fieldKey": "pasgarBellyCount",
          "names": {
            "en": "Belly",
            "ar": "البطن"
          },
          "aliases": {
            "en": [
              "belly"
            ],
            "ar": [
              "البطن",
              "بطن"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarBellyCount"
          },
          "persistence": {
            "localColumn": "pasgarBellyCount",
            "remoteColumn": "pasgar_belly_count"
          }
        },
        {
          "fieldKey": "pasgarLegCount",
          "names": {
            "en": "Legs",
            "ar": "الأرجل"
          },
          "aliases": {
            "en": [
              "leg",
              "legs"
            ],
            "ar": [
              "الأرجل",
              "الارجل",
              "رجل"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarLegCount"
          },
          "persistence": {
            "localColumn": "pasgarLegCount",
            "remoteColumn": "pasgar_leg_count"
          }
        },
        {
          "fieldKey": "pasgarFeatherDevCount",
          "names": {
            "en": "Feather development",
            "ar": "تطور الريش"
          },
          "aliases": {
            "en": [
              "feather",
              "feather development"
            ],
            "ar": [
              "الريش",
              "تطور الريش"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pasgarSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pasgarFeatherDevCount"
          },
          "persistence": {
            "localColumn": "pasgarFeatherDevCount",
            "remoteColumn": "pasgar_feather_dev_count"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "pasgarReflexesPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarReflexesCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarReflexesPct",
            "remoteColumn": "pasgar_reflexes_pct"
          }
        },
        {
          "fieldKey": "pasgarBeakPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarBeakCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarBeakPct",
            "remoteColumn": "pasgar_beak_pct"
          }
        },
        {
          "fieldKey": "pasgarNavelPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarNavelCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarNavelPct",
            "remoteColumn": "pasgar_navel_pct"
          }
        },
        {
          "fieldKey": "pasgarBellyPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarBellyCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarBellyPct",
            "remoteColumn": "pasgar_belly_pct"
          }
        },
        {
          "fieldKey": "pasgarLegPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarLegCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarLegPct",
            "remoteColumn": "pasgar_leg_pct"
          }
        },
        {
          "fieldKey": "pasgarFeatherDevPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "pasgarFeatherDevCount",
            "pasgarSampleSize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "pasgarFeatherDevPct",
            "remoteColumn": "pasgar_feather_dev_pct"
          }
        },
        {
          "fieldKey": "pasgarFinalScore",
          "kind": "pasgar_score",
          "inputFieldKeys": [
            "pasgarSampleSize",
            "pasgarReflexesCount",
            "pasgarBeakCount",
            "pasgarNavelCount",
            "pasgarBellyCount",
            "pasgarLegCount"
          ],
          "unit": "score",
          "persistence": {
            "localColumn": "pasgarFinalScore",
            "remoteColumn": "pasgar_final_score"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "pasgarSampleSize",
          "pasgarReflexesCount",
          "pasgarBeakCount",
          "pasgarNavelCount",
          "pasgarBellyCount",
          "pasgarLegCount",
          "pasgarFeatherDevCount"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_quality",
          "remoteTable": "chick_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter",
          "hatcher"
        ],
        "measures": [
          "pasgarSampleSize",
          "pasgarReflexesCount",
          "pasgarBeakCount",
          "pasgarNavelCount",
          "pasgarBellyCount",
          "pasgarLegCount",
          "pasgarFeatherDevCount",
          "pasgarReflexesPct",
          "pasgarBeakPct",
          "pasgarNavelPct",
          "pasgarBellyPct",
          "pasgarLegPct",
          "pasgarFeatherDevPct",
          "pasgarFinalScore"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "egg.storage_environment",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "egg",
      "moduleKey": "storage_environment",
      "names": {
        "en": "Egg Storage — Environment",
        "ar": "تخزين البيض — البيئة"
      },
      "aliases": {
        "en": [
          "egg storage",
          "storage checklist"
        ],
        "ar": [
          "تخزين البيض",
          "قائمة التخزين"
        ]
      },
      "allowedLayers": [
        "pool"
      ],
      "fields": [
        {
          "fieldKey": "storagePeriodDays",
          "names": {
            "en": "Storage period",
            "ar": "مدة التخزين"
          },
          "aliases": {
            "en": [
              "storage days",
              "storage period"
            ],
            "ar": [
              "أيام التخزين",
              "مدة التخزين"
            ]
          },
          "type": "integer",
          "unit": "days",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 60
          },
          "persistence": {
            "localColumn": "storagePeriodDays",
            "remoteColumn": "storage_period_days"
          }
        },
        {
          "fieldKey": "turningTimes",
          "names": {
            "en": "Turning times per day",
            "ar": "مرات التقليب يوميًا"
          },
          "aliases": {
            "en": [
              "turning times",
              "turns per day"
            ],
            "ar": [
              "مرات التقليب",
              "التقليب يوميا"
            ]
          },
          "type": "integer",
          "unit": "times_per_day",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 24
          },
          "persistence": {
            "localColumn": "turningTimes",
            "remoteColumn": "turning_times"
          }
        },
        {
          "fieldKey": "traySpacing",
          "names": {
            "en": "Tray spacing",
            "ar": "المسافة بين الصواني"
          },
          "aliases": {
            "en": [
              "tray spacing",
              "spacing"
            ],
            "ar": [
              "مسافة الصواني",
              "المسافة بين الصواني"
            ]
          },
          "type": "string",
          "unit": "status",
          "required": true,
          "explicitZero": false,
          "validation": {
            "choices": [
              "adequate",
              "inadequate"
            ]
          },
          "persistence": {
            "localColumn": "traySpacing",
            "remoteColumn": "tray_spacing"
          }
        },
        {
          "fieldKey": "coolerProximity",
          "names": {
            "en": "Cooler proximity",
            "ar": "القرب من المبرد"
          },
          "aliases": {
            "en": [
              "cooler proximity",
              "near cooler"
            ],
            "ar": [
              "القرب من المبرد",
              "بجوار المبرد"
            ]
          },
          "type": "string",
          "unit": "status",
          "required": true,
          "explicitZero": false,
          "validation": {
            "choices": [
              "clear",
              "too_close"
            ]
          },
          "persistence": {
            "localColumn": "coolerProximity",
            "remoteColumn": "cooler_proximity"
          }
        },
        {
          "fieldKey": "condensationPresent",
          "names": {
            "en": "Condensation present",
            "ar": "وجود تكثف"
          },
          "aliases": {
            "en": [
              "condensation",
              "water condensation"
            ],
            "ar": [
              "تكثف",
              "وجود ماء متكثف"
            ]
          },
          "type": "boolean",
          "unit": "boolean",
          "required": true,
          "explicitZero": false,
          "validation": {},
          "persistence": {
            "localColumn": "condensationPresent",
            "remoteColumn": "condensation_present",
            "encoding": "integer_boolean"
          }
        }
      ],
      "calculations": [],
      "completion": {
        "requiredFieldKeys": [
          "storagePeriodDays",
          "turningTimes",
          "traySpacing",
          "coolerProximity",
          "condensationPresent"
        ]
      },
      "persistence": [
        {
          "localTable": "egg_storage",
          "remoteTable": "egg_storage"
        }
      ],
      "read": {
        "dimensions": [
          "date"
        ],
        "measures": [
          "storagePeriodDays",
          "turningTimes",
          "traySpacing",
          "coolerProximity",
          "condensationPresent"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "egg.shell_temperature",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "egg",
      "moduleKey": "shell_temperature",
      "names": {
        "en": "Egg Storage — Shell Temperature",
        "ar": "تخزين البيض — حرارة القشرة"
      },
      "aliases": {
        "en": [
          "egg shell temperature",
          "est"
        ],
        "ar": [
          "حرارة قشرة البيض",
          "حرارة القشرة"
        ]
      },
      "allowedLayers": [
        "pool"
      ],
      "fields": [
        {
          "fieldKey": "estReadingsJson",
          "names": {
            "en": "Shell temperature readings",
            "ar": "قراءات حرارة القشرة"
          },
          "aliases": {
            "en": [
              "est readings",
              "shell temperatures"
            ],
            "ar": [
              "قراءات الحرارة",
              "حرارة القشرة"
            ]
          },
          "type": "number_list",
          "unit": "celsius",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 0,
            "itemMax": 60
          },
          "persistence": {
            "localColumn": "estReadingsJson",
            "remoteColumn": "est_readings_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "estAvg",
          "kind": "series_average",
          "inputFieldKeys": [
            "estReadingsJson"
          ],
          "unit": "celsius",
          "persistence": {
            "localColumn": "estAvg",
            "remoteColumn": "est_avg"
          }
        },
        {
          "fieldKey": "estCvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "estReadingsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "estCvPct",
            "remoteColumn": "est_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "estReadingsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "egg_storage",
          "remoteTable": "egg_storage"
        }
      ],
      "read": {
        "dimensions": [
          "date"
        ],
        "measures": [
          "estAvg",
          "estCvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "egg.upside_down",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "egg",
      "moduleKey": "upside_down",
      "names": {
        "en": "Egg Storage — Upside Down",
        "ar": "تخزين البيض — البيض المقلوب"
      },
      "aliases": {
        "en": [
          "upside down eggs",
          "inverted eggs"
        ],
        "ar": [
          "البيض المقلوب",
          "بيض مقلوب"
        ]
      },
      "allowedLayers": [
        "pool"
      ],
      "fields": [
        {
          "fieldKey": "upsideDownCount",
          "names": {
            "en": "Upside-down eggs",
            "ar": "عدد البيض المقلوب"
          },
          "aliases": {
            "en": [
              "upside down count",
              "inverted count"
            ],
            "ar": [
              "عدد البيض المقلوب",
              "المقلوب"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0
          },
          "persistence": {
            "localColumn": "upsideDownCount",
            "remoteColumn": "upside_down_count"
          }
        }
      ],
      "calculations": [],
      "completion": {
        "requiredFieldKeys": [
          "upsideDownCount"
        ]
      },
      "persistence": [
        {
          "localTable": "egg_storage",
          "remoteTable": "egg_storage"
        }
      ],
      "read": {
        "dimensions": [
          "date"
        ],
        "measures": [
          "upsideDownCount",
          "upsideDownPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "egg.quality_uv",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "egg",
      "moduleKey": "quality_uv",
      "names": {
        "en": "Egg Quality — UV Shell Check",
        "ar": "جودة البيض — فحص القشرة بالأشعة"
      },
      "aliases": {
        "en": [
          "uv shell quality",
          "cuticle check"
        ],
        "ar": [
          "فحص القشرة",
          "فحص الكيوتيكل"
        ]
      },
      "allowedLayers": [
        "pool",
        "house"
      ],
      "fields": [
        {
          "fieldKey": "uvTrayEggCount",
          "names": {
            "en": "Eggs checked",
            "ar": "عدد البيض المفحوص"
          },
          "aliases": {
            "en": [
              "eggs checked",
              "uv sample"
            ],
            "ar": [
              "البيض المفحوص",
              "عينة الأشعة"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1
          },
          "persistence": {
            "localColumn": "uvTrayEggCount",
            "remoteColumn": "uv_tray_egg_count"
          }
        },
        {
          "fieldKey": "uvCuticleDamageCount",
          "names": {
            "en": "Cuticle damage",
            "ar": "تلف الكيوتيكل"
          },
          "aliases": {
            "en": [
              "cuticle damage",
              "damaged cuticle"
            ],
            "ar": [
              "تلف الكيوتيكل",
              "قشرة متضررة"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "uvTrayEggCount"
          },
          "persistence": {
            "localColumn": "uvCuticleDamageCount",
            "remoteColumn": "uv_cuticle_damage_count"
          }
        },
        {
          "fieldKey": "uvWashedCount",
          "names": {
            "en": "Washed eggs",
            "ar": "البيض المغسول"
          },
          "aliases": {
            "en": [
              "washed eggs",
              "washed"
            ],
            "ar": [
              "البيض المغسول",
              "مغسول"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "uvTrayEggCount"
          },
          "persistence": {
            "localColumn": "uvWashedCount",
            "remoteColumn": "uv_washed_count"
          }
        },
        {
          "fieldKey": "uvDirtyCount",
          "names": {
            "en": "Dirty eggs",
            "ar": "البيض المتسخ"
          },
          "aliases": {
            "en": [
              "dirty eggs",
              "dirty"
            ],
            "ar": [
              "البيض المتسخ",
              "متسخ"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "uvTrayEggCount"
          },
          "persistence": {
            "localColumn": "uvDirtyCount",
            "remoteColumn": "uv_dirty_count"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "uvCuticleDamagePct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "uvCuticleDamageCount",
            "uvTrayEggCount"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "uvCuticleDamagePct",
            "remoteColumn": "uv_cuticle_damage_pct"
          }
        },
        {
          "fieldKey": "uvWashedPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "uvWashedCount",
            "uvTrayEggCount"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "uvWashedPct",
            "remoteColumn": "uv_washed_pct"
          }
        },
        {
          "fieldKey": "uvDirtyPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "uvDirtyCount",
            "uvTrayEggCount"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "uvDirtyPct",
            "remoteColumn": "uv_dirty_pct"
          }
        },
        {
          "fieldKey": "uvAffectedCount",
          "kind": "sum",
          "inputFieldKeys": [
            "uvCuticleDamageCount",
            "uvWashedCount",
            "uvDirtyCount"
          ],
          "unit": "eggs",
          "persistence": {
            "localColumn": "uvAffectedCount",
            "remoteColumn": "uv_affected_count"
          }
        },
        {
          "fieldKey": "uvAffectedPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "uvAffectedCount",
            "uvTrayEggCount"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "uvAffectedPct",
            "remoteColumn": "uv_affected_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "uvTrayEggCount",
          "uvCuticleDamageCount",
          "uvWashedCount",
          "uvDirtyCount"
        ]
      },
      "persistence": [
        {
          "localTable": "egg_quality",
          "remoteTable": "egg_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house"
        ],
        "measures": [
          "uvTrayEggCount",
          "uvAffectedPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "egg.weights",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "egg",
      "moduleKey": "weights",
      "names": {
        "en": "Egg Quality — Weights",
        "ar": "جودة البيض — الأوزان"
      },
      "aliases": {
        "en": [
          "egg weights",
          "egg weight sample"
        ],
        "ar": [
          "أوزان البيض",
          "عينة وزن البيض"
        ]
      },
      "allowedLayers": [
        "pool",
        "house"
      ],
      "fields": [
        {
          "fieldKey": "eggWeightsJson",
          "names": {
            "en": "Egg weights",
            "ar": "أوزان البيض"
          },
          "aliases": {
            "en": [
              "weights",
              "egg weights"
            ],
            "ar": [
              "الأوزان",
              "أوزان البيض"
            ]
          },
          "type": "number_list",
          "unit": "grams",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 1,
            "itemMax": 200
          },
          "persistence": {
            "localColumn": "eggWeightsJson",
            "remoteColumn": "egg_weights_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "eggSampleSize",
          "kind": "series_sample_size",
          "inputFieldKeys": [
            "eggWeightsJson"
          ],
          "unit": "eggs",
          "persistence": {
            "localColumn": "eggSampleSize",
            "remoteColumn": "egg_sample_size"
          }
        },
        {
          "fieldKey": "eggAvgWeight",
          "kind": "series_average",
          "inputFieldKeys": [
            "eggWeightsJson"
          ],
          "unit": "grams",
          "persistence": {
            "localColumn": "eggAvgWeight",
            "remoteColumn": "egg_avg_weight"
          }
        },
        {
          "fieldKey": "eggUniformityPct",
          "kind": "series_uniformity_10pct",
          "inputFieldKeys": [
            "eggWeightsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "eggUniformityPct",
            "remoteColumn": "egg_uniformity_pct"
          }
        },
        {
          "fieldKey": "eggCvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "eggWeightsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "eggCvPct",
            "remoteColumn": "egg_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "eggWeightsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "egg_quality",
          "remoteTable": "egg_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house"
        ],
        "measures": [
          "eggSampleSize",
          "eggAvgWeight",
          "eggUniformityPct",
          "eggCvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "chicks.yfbm",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "yfbm",
      "names": {
        "en": "Chick Quality — YFBM",
        "ar": "جودة الكتاكيت — كتلة الصفار"
      },
      "aliases": {
        "en": [
          "yfbm",
          "yolk free body mass"
        ],
        "ar": [
          "كتلة الجسم بدون صفار",
          "كتلة الصفار"
        ]
      },
      "allowedLayers": [
        "pool",
        "setter_hatcher"
      ],
      "photoEvidence": {
        "yfbm_photo": null
      },
      "fields": [
        {
          "fieldKey": "yfbmEntriesJson",
          "names": {
            "en": "YFBM entries",
            "ar": "قياسات كتلة الجسم بدون صفار"
          },
          "aliases": {
            "en": [
              "yfbm entries",
              "body and yolk weights"
            ],
            "ar": [
              "قياسات الكتلة",
              "وزن الجسم والصفار"
            ]
          },
          "type": "object_list",
          "unit": "grams",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "maxItems": 500,
            "itemSchema": {
              "required": [
                "chickWeight",
                "yolkWeight"
              ],
              "properties": {
                "chickWeight": {
                  "type": "number",
                  "min": 1,
                  "max": 200
                },
                "yolkWeight": {
                  "type": "number",
                  "min": 0,
                  "maxPropertyKey": "chickWeight"
                }
              }
            }
          },
          "observation": {
            "kind": "series",
            "properties": {
              "chickWeight": {
                "key": "yfbm:chickWeight",
                "valueType": "number"
              },
              "yolkWeight": {
                "key": "yfbm:yolkWeight",
                "valueType": "number"
              }
            }
          },
          "persistence": {
            "localColumn": "yfbmEntriesJson",
            "remoteColumn": "yfbm_entries_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "yfbmEntryCount",
          "kind": "yfbm_entry_count",
          "inputFieldKeys": [
            "yfbmEntriesJson"
          ],
          "unit": "chicks",
          "persistence": {
            "localColumn": "yfbmEntryCount",
            "remoteColumn": "yfbm_entry_count"
          }
        },
        {
          "fieldKey": "yfbmAvgPct",
          "kind": "yfbm_average_pct",
          "inputFieldKeys": [
            "yfbmEntriesJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "yfbmAvgPct",
            "remoteColumn": "yfbm_avg_pct"
          }
        },
        {
          "fieldKey": "yfbmCvPct",
          "kind": "yfbm_cv_pct",
          "inputFieldKeys": [
            "yfbmEntriesJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "yfbmCvPct",
            "remoteColumn": "yfbm_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "yfbmEntriesJson"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_quality",
          "remoteTable": "chick_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter",
          "hatcher"
        ],
        "measures": [
          "yfbmEntryCount",
          "yfbmAvgPct",
          "yfbmCvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "chicks.cvt",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "cvt",
      "names": {
        "en": "Chick Quality — Vent Temperature",
        "ar": "جودة الكتاكيت — حرارة المخرج"
      },
      "aliases": {
        "en": [
          "cvt",
          "chick vent temperature"
        ],
        "ar": [
          "حرارة مخرج الكتكوت",
          "حرارة الكتاكيت"
        ]
      },
      "allowedLayers": [
        "pool",
        "setter_hatcher"
      ],
      "photoEvidence": {
        "cvt": null
      },
      "fields": [
        {
          "fieldKey": "cvtReadingsJson",
          "names": {
            "en": "Vent temperature readings",
            "ar": "قراءات حرارة المخرج"
          },
          "aliases": {
            "en": [
              "cvt readings",
              "vent temperatures"
            ],
            "ar": [
              "قراءات حرارة المخرج",
              "درجات حرارة الكتاكيت"
            ]
          },
          "type": "number_list",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 80,
            "itemMax": 110
          },
          "observation": {
            "kind": "series",
            "key": "cvtReadingsJson"
          },
          "persistence": {
            "localColumn": "cvtReadingsJson",
            "remoteColumn": "cvt_readings_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "cvtSampleSize",
          "kind": "series_sample_size",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "chicks",
          "persistence": {
            "localColumn": "cvtSampleSize",
            "remoteColumn": "cvt_sample_size"
          }
        },
        {
          "fieldKey": "cvtAvgTemp",
          "kind": "series_average",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "fahrenheit",
          "persistence": {
            "localColumn": "cvtAvgTemp",
            "remoteColumn": "cvt_avg_temp"
          }
        },
        {
          "fieldKey": "cvtCvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "cvtCvPct",
            "remoteColumn": "cvt_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "cvtReadingsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_quality",
          "remoteTable": "chick_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter",
          "hatcher"
        ],
        "measures": [
          "cvtSampleSize",
          "cvtAvgTemp",
          "cvtCvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "chicks.postmortem",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "postmortem",
      "names": {
        "en": "Chick Quality — PM Necropsy",
        "ar": "جودة الكتاكيت — التشريح"
      },
      "aliases": {
        "en": [
          "pm necropsy",
          "postmortem"
        ],
        "ar": [
          "التشريح",
          "فحص ما بعد النفوق"
        ]
      },
      "allowedLayers": [
        "pool",
        "setter_hatcher"
      ],
      "photoEvidence": {
        "pm_photo": null
      },
      "fields": [
        {
          "fieldKey": "pmSampleSize",
          "names": {
            "en": "Necropsy sample size",
            "ar": "حجم عينة التشريح"
          },
          "aliases": {
            "en": [
              "pm sample",
              "necropsy sample"
            ],
            "ar": [
              "عينة التشريح",
              "عدد التشريح"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 500
          },
          "observation": {
            "kind": "tally",
            "key": "pmSampleSize"
          },
          "persistence": {
            "localColumn": "pmSampleSize",
            "remoteColumn": "pm_sample_size"
          }
        },
        {
          "fieldKey": "pmCollectionPoint",
          "names": {
            "en": "Collection point",
            "ar": "نقطة جمع العينة"
          },
          "aliases": {
            "en": [
              "collection point",
              "sample location"
            ],
            "ar": [
              "نقطة الجمع",
              "مكان العينة"
            ]
          },
          "type": "string",
          "unit": "text",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minLength": 1
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmCollectionPoint"
          },
          "persistence": {
            "localColumn": "pmCollectionPoint",
            "remoteColumn": "pm_collection_point"
          }
        },
        {
          "fieldKey": "pmOmphalitisCount",
          "names": {
            "en": "Omphalitis",
            "ar": "التهاب السرة"
          },
          "aliases": {
            "en": [
              "omphalitis"
            ],
            "ar": [
              "التهاب السرة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmOmphalitisCount"
          },
          "persistence": {
            "localColumn": "pmOmphalitisCount",
            "remoteColumn": "pm_omphalitis_count"
          }
        },
        {
          "fieldKey": "pmOmphalitisSeverity",
          "names": {
            "en": "Omphalitis severity",
            "ar": "شدة التهاب السرة"
          },
          "aliases": {
            "en": [
              "omphalitis severity"
            ],
            "ar": [
              "شدة التهاب السرة"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmOmphalitisCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmOmphalitisSeverity"
          },
          "persistence": {
            "localColumn": "pmOmphalitisSeverity",
            "remoteColumn": "pm_omphalitis_severity"
          }
        },
        {
          "fieldKey": "pmGaseousCecaCount",
          "names": {
            "en": "Gaseous ceca",
            "ar": "غازات الأعورين"
          },
          "aliases": {
            "en": [
              "gaseous ceca"
            ],
            "ar": [
              "غازات الأعورين"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmGaseousCecaCount"
          },
          "persistence": {
            "localColumn": "pmGaseousCecaCount",
            "remoteColumn": "pm_gaseous_ceca_count"
          }
        },
        {
          "fieldKey": "pmGaseousCecaSeverity",
          "names": {
            "en": "Gaseous ceca severity",
            "ar": "شدة غازات الأعورين"
          },
          "aliases": {
            "en": [
              "gaseous ceca severity"
            ],
            "ar": [
              "شدة غازات الأعورين"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmGaseousCecaCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmGaseousCecaSeverity"
          },
          "persistence": {
            "localColumn": "pmGaseousCecaSeverity",
            "remoteColumn": "pm_gaseous_ceca_severity"
          }
        },
        {
          "fieldKey": "pmGizzardErosionsCount",
          "names": {
            "en": "Gizzard erosions",
            "ar": "تآكل القانصة"
          },
          "aliases": {
            "en": [
              "gizzard erosions"
            ],
            "ar": [
              "تآكل القانصة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmGizzardErosionsCount"
          },
          "persistence": {
            "localColumn": "pmGizzardErosionsCount",
            "remoteColumn": "pm_gizzard_erosions_count"
          }
        },
        {
          "fieldKey": "pmGizzardErosionsSeverity",
          "names": {
            "en": "Gizzard erosion severity",
            "ar": "شدة تآكل القانصة"
          },
          "aliases": {
            "en": [
              "gizzard severity"
            ],
            "ar": [
              "شدة تآكل القانصة"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmGizzardErosionsCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmGizzardErosionsSeverity"
          },
          "persistence": {
            "localColumn": "pmGizzardErosionsSeverity",
            "remoteColumn": "pm_gizzard_erosions_severity"
          }
        },
        {
          "fieldKey": "pmAirSacCaseationsCount",
          "names": {
            "en": "Air sac caseations",
            "ar": "تجبن الأكياس الهوائية"
          },
          "aliases": {
            "en": [
              "air sac caseations"
            ],
            "ar": [
              "تجبن الأكياس الهوائية"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmAirSacCaseationsCount"
          },
          "persistence": {
            "localColumn": "pmAirSacCaseationsCount",
            "remoteColumn": "pm_air_sac_caseations_count"
          }
        },
        {
          "fieldKey": "pmAirSacCaseationsSeverity",
          "names": {
            "en": "Air sac caseation severity",
            "ar": "شدة تجبن الأكياس الهوائية"
          },
          "aliases": {
            "en": [
              "air sac severity"
            ],
            "ar": [
              "شدة تجبن الأكياس الهوائية"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmAirSacCaseationsCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmAirSacCaseationsSeverity"
          },
          "persistence": {
            "localColumn": "pmAirSacCaseationsSeverity",
            "remoteColumn": "pm_air_sac_caseations_severity"
          }
        },
        {
          "fieldKey": "pmUrolithiasisCount",
          "names": {
            "en": "Urolithiasis",
            "ar": "ترسبات اليورات"
          },
          "aliases": {
            "en": [
              "urolithiasis",
              "urate deposits"
            ],
            "ar": [
              "ترسبات اليورات"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmUrolithiasisCount"
          },
          "persistence": {
            "localColumn": "pmUrolithiasisCount",
            "remoteColumn": "pm_urolithiasis_count"
          }
        },
        {
          "fieldKey": "pmUrolithiasisSeverity",
          "names": {
            "en": "Urolithiasis severity",
            "ar": "شدة ترسبات اليورات"
          },
          "aliases": {
            "en": [
              "urolithiasis severity"
            ],
            "ar": [
              "شدة ترسبات اليورات"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmUrolithiasisCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmUrolithiasisSeverity"
          },
          "persistence": {
            "localColumn": "pmUrolithiasisSeverity",
            "remoteColumn": "pm_urolithiasis_severity"
          }
        },
        {
          "fieldKey": "pmNephritisCount",
          "names": {
            "en": "Nephritis",
            "ar": "التهاب الكلى"
          },
          "aliases": {
            "en": [
              "nephritis"
            ],
            "ar": [
              "التهاب الكلى"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmNephritisCount"
          },
          "persistence": {
            "localColumn": "pmNephritisCount",
            "remoteColumn": "pm_nephritis_count"
          }
        },
        {
          "fieldKey": "pmNephritisSeverity",
          "names": {
            "en": "Nephritis severity",
            "ar": "شدة التهاب الكلى"
          },
          "aliases": {
            "en": [
              "nephritis severity"
            ],
            "ar": [
              "شدة التهاب الكلى"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmNephritisCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmNephritisSeverity"
          },
          "persistence": {
            "localColumn": "pmNephritisSeverity",
            "remoteColumn": "pm_nephritis_severity"
          }
        },
        {
          "fieldKey": "pmGeneralSepticemiaCount",
          "names": {
            "en": "General septicemia",
            "ar": "تسمم دموي عام"
          },
          "aliases": {
            "en": [
              "general septicemia",
              "septicemia"
            ],
            "ar": [
              "تسمم دموي عام"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "pmSampleSize"
          },
          "observation": {
            "kind": "tally",
            "key": "pmGeneralSepticemiaCount"
          },
          "persistence": {
            "localColumn": "pmGeneralSepticemiaCount",
            "remoteColumn": "pm_general_septicemia_count"
          }
        },
        {
          "fieldKey": "pmGeneralSepticemiaSeverity",
          "names": {
            "en": "Septicemia severity",
            "ar": "شدة التسمم الدموي"
          },
          "aliases": {
            "en": [
              "septicemia severity"
            ],
            "ar": [
              "شدة التسمم الدموي"
            ]
          },
          "type": "string",
          "unit": "severity",
          "required": false,
          "explicitZero": false,
          "validation": {
            "choices": [
              "Mild",
              "Moderate",
              "Severe"
            ],
            "requiredWhenPositiveFieldKey": "pmGeneralSepticemiaCount"
          },
          "observation": {
            "kind": "ordinal",
            "key": "pmGeneralSepticemiaSeverity"
          },
          "persistence": {
            "localColumn": "pmGeneralSepticemiaSeverity",
            "remoteColumn": "pm_general_septicemia_severity"
          }
        }
      ],
      "calculations": [],
      "completion": {
        "requiredFieldKeys": [
          "pmSampleSize",
          "pmCollectionPoint",
          "pmOmphalitisCount",
          "pmGaseousCecaCount",
          "pmGizzardErosionsCount",
          "pmAirSacCaseationsCount",
          "pmUrolithiasisCount",
          "pmNephritisCount",
          "pmGeneralSepticemiaCount"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_quality",
          "remoteTable": "chick_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter",
          "hatcher"
        ],
        "measures": [
          "pmSampleSize",
          "pmSuspectedCauseAuto",
          "pmSuspectedCauseManual"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "chicks.culled_analysis",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "culled_analysis",
      "names": {
        "en": "Chick Quality — Culled Analysis",
        "ar": "جودة الكتاكيت — تحليل المستبعد"
      },
      "aliases": {
        "en": [
          "culled chicks analysis",
          "cull analysis"
        ],
        "ar": [
          "تحليل الكتاكيت المستبعدة",
          "تحليل المستبعد"
        ]
      },
      "allowedLayers": [
        "pool",
        "setter_hatcher"
      ],
      "fields": [
        {
          "fieldKey": "culledChicksTotalEggSet",
          "names": {
            "en": "Total eggs set",
            "ar": "إجمالي البيض المحضن"
          },
          "aliases": {
            "en": [
              "total eggs set",
              "eggs set"
            ],
            "ar": [
              "إجمالي البيض",
              "البيض المحضن"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 10000000
          },
          "observation": {
            "kind": "tally",
            "key": "culledChicksTotalEggSet"
          },
          "persistence": {
            "localColumn": "culledChicksTotalEggSet",
            "remoteColumn": "culled_chicks_total_egg_set"
          }
        },
        {
          "fieldKey": "culledChicksAnalysisJson",
          "names": {
            "en": "Culled chick observations",
            "ar": "ملاحظات الكتاكيت المستبعدة"
          },
          "aliases": {
            "en": [
              "culled observations",
              "cull defects"
            ],
            "ar": [
              "ملاحظات المستبعد",
              "عيوب الكتاكيت"
            ]
          },
          "type": "object_list",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "minItems": 0,
            "maxItems": 17,
            "itemSchema": {
              "required": [
                "id",
                "count"
              ],
              "properties": {
                "id": {
                  "type": "string",
                  "choices": [
                    "navel_open_unhealed",
                    "navel_string",
                    "navel_black_button",
                    "navel_residual_yolk_large_abdomen",
                    "sticky_sticky_chick",
                    "sticky_dehydrated_burned_chick",
                    "legs_spraddle_leg",
                    "legs_curled_toes",
                    "legs_twisted_legs_feet",
                    "legs_red_hocks",
                    "head_crossed_crooked_beak",
                    "head_missing_eye_one_eye",
                    "head_exposed_brain",
                    "neuro_stargazer_nervous_signs",
                    "neuro_wry_neck",
                    "small_weak_small_chick",
                    "hair_chick_sparse_down"
                  ]
                },
                "count": {
                  "type": "integer",
                  "min": 1,
                  "maxFieldKey": "culledChicksTotalEggSet"
                }
              }
            }
          },
          "observation": {
            "kind": "tally",
            "keyProperty": "id",
            "valueProperty": "count",
            "keyPrefix": "culled:",
            "presenceKey": "culled:__present",
            "ignoredProperties": [
              "category",
              "subtype",
              "description",
              "commonCauses",
              "sourceRefs",
              "pct"
            ]
          },
          "persistence": {
            "localColumn": "culledChicksAnalysisJson",
            "remoteColumn": "culled_chicks_analysis_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "culledChicksAffectedPct",
          "kind": "culled_affected_pct",
          "inputFieldKeys": [
            "culledChicksTotalEggSet",
            "culledChicksAnalysisJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "culledChicksAffectedPct",
            "remoteColumn": "culled_chicks_affected_pct"
          }
        },
        {
          "fieldKey": "culledChicksTopCategory",
          "kind": "culled_top_category",
          "inputFieldKeys": [
            "culledChicksAnalysisJson"
          ],
          "unit": "text",
          "persistence": {
            "localColumn": "culledChicksTopCategory",
            "remoteColumn": "culled_chicks_top_category"
          }
        },
        {
          "fieldKey": "culledChicksTopSubtype",
          "kind": "culled_top_subtype",
          "inputFieldKeys": [
            "culledChicksAnalysisJson"
          ],
          "unit": "text",
          "persistence": {
            "localColumn": "culledChicksTopSubtype",
            "remoteColumn": "culled_chicks_top_subtype"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "culledChicksTotalEggSet",
          "culledChicksAnalysisJson"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_quality",
          "remoteTable": "chick_quality"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter",
          "hatcher"
        ],
        "measures": [
          "culledChicksAffectedPct",
          "culledChicksTopCategory",
          "culledChicksTopSubtype"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "chicks.weights",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "chicks",
      "moduleKey": "weights",
      "names": {
        "en": "Chick Quality — Weights",
        "ar": "جودة الكتاكيت — الأوزان"
      },
      "aliases": {
        "en": [
          "chick weights",
          "chick weight sample"
        ],
        "ar": [
          "أوزان الكتاكيت",
          "عينة وزن الكتاكيت"
        ]
      },
      "allowedLayers": [
        "pool",
        "house"
      ],
      "fields": [
        {
          "fieldKey": "weightsJson",
          "names": {
            "en": "Chick weights",
            "ar": "أوزان الكتاكيت"
          },
          "aliases": {
            "en": [
              "weights",
              "chick weights"
            ],
            "ar": [
              "الأوزان",
              "أوزان الكتاكيت"
            ]
          },
          "type": "number_list",
          "unit": "grams",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 1,
            "itemMax": 200
          },
          "observation": {
            "kind": "series",
            "key": "weightsJson"
          },
          "persistence": {
            "localColumn": "weightsJson",
            "remoteColumn": "weights_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "sampleSize",
          "kind": "series_sample_size",
          "inputFieldKeys": [
            "weightsJson"
          ],
          "unit": "chicks",
          "persistence": {
            "localColumn": "sampleSize",
            "remoteColumn": "sample_size"
          }
        },
        {
          "fieldKey": "avgWeight",
          "kind": "series_average",
          "inputFieldKeys": [
            "weightsJson"
          ],
          "unit": "grams",
          "persistence": {
            "localColumn": "avgWeight",
            "remoteColumn": "avg_weight"
          }
        },
        {
          "fieldKey": "uniformityPct",
          "kind": "series_uniformity_10pct",
          "inputFieldKeys": [
            "weightsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "uniformityPct",
            "remoteColumn": "uniformity_pct"
          }
        },
        {
          "fieldKey": "cvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "weightsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "cvPct",
            "remoteColumn": "cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "weightsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "chick_weights",
          "remoteTable": "chick_weights"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house"
        ],
        "measures": [
          "sampleSize",
          "avgWeight",
          "uniformityPct",
          "cvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "hatch_analysis.fresh_breakout",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "hatch_analysis_egg_breakouts",
      "moduleKey": "fresh_breakout",
      "names": {
        "en": "Hatch Analysis — Fresh Egg Breakout",
        "ar": "تحليل الفقس — كسر البيض الطازج"
      },
      "aliases": {
        "en": [
          "fresh breakout",
          "fresh egg breakout"
        ],
        "ar": [
          "كسر البيض الطازج",
          "الكسر الطازج"
        ]
      },
      "allowedLayers": [
        "pool",
        "house",
        "tray"
      ],
      "fields": [
        {
          "fieldKey": "traySize",
          "names": {
            "en": "Tray size",
            "ar": "حجم الصينية"
          },
          "aliases": {
            "en": [
              "tray size",
              "sample eggs"
            ],
            "ar": [
              "حجم الصينية",
              "عدد البيض"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 500
          },
          "persistence": {
            "localColumn": "traySize",
            "remoteColumn": "tray_size"
          }
        },
        {
          "fieldKey": "infertileCount",
          "names": {
            "en": "Infertile",
            "ar": "غير مخصب"
          },
          "aliases": {
            "en": [
              "infertile",
              "clear eggs"
            ],
            "ar": [
              "غير مخصب",
              "بيض صافي"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "infertileCount",
            "remoteColumn": "infertile_count"
          }
        },
        {
          "fieldKey": "early24hCount",
          "names": {
            "en": "Early dead 24 hours",
            "ar": "نفوق مبكر 24 ساعة"
          },
          "aliases": {
            "en": [
              "24 hour dead",
              "early 24"
            ],
            "ar": [
              "نفوق 24 ساعة",
              "مبكر 24"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "early24hCount",
            "remoteColumn": "early24h_count"
          }
        },
        {
          "fieldKey": "early48hCount",
          "names": {
            "en": "Early dead 48 hours",
            "ar": "نفوق مبكر 48 ساعة"
          },
          "aliases": {
            "en": [
              "48 hour dead",
              "early 48"
            ],
            "ar": [
              "نفوق 48 ساعة",
              "مبكر 48"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "early48hCount",
            "remoteColumn": "early48h_count"
          }
        },
        {
          "fieldKey": "bloodRingCount",
          "names": {
            "en": "Blood ring",
            "ar": "حلقة دموية"
          },
          "aliases": {
            "en": [
              "blood ring"
            ],
            "ar": [
              "حلقة دموية",
              "حلقة الدم"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "bloodRingCount",
            "remoteColumn": "blood_ring_count"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "infertilePct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "infertileCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "infertilePct",
            "remoteColumn": "infertile_pct"
          }
        },
        {
          "fieldKey": "early24hPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "early24hCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "early24hPct",
            "remoteColumn": "early24h_pct"
          }
        },
        {
          "fieldKey": "early48hPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "early48hCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "early48hPct",
            "remoteColumn": "early48h_pct"
          }
        },
        {
          "fieldKey": "bloodRingPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "bloodRingCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "bloodRingPct",
            "remoteColumn": "blood_ring_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "traySize",
          "infertileCount",
          "early24hCount",
          "early48hCount",
          "bloodRingCount"
        ]
      },
      "persistence": [
        {
          "localTable": "fresh_egg_breakout",
          "remoteTable": "fresh_egg_breakout"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house",
          "tray"
        ],
        "measures": [
          "traySize",
          "infertilePct",
          "early24hPct",
          "early48hPct",
          "bloodRingPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "hatch_analysis.candled_breakout",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "hatch_analysis_egg_breakouts",
      "moduleKey": "candled_breakout",
      "names": {
        "en": "Hatch Analysis — Candled Breakout",
        "ar": "تحليل الفقس — كسر البيض المفحوص"
      },
      "aliases": {
        "en": [
          "candled breakout",
          "candling breakout"
        ],
        "ar": [
          "كسر البيض المفحوص",
          "كسر التسقيط"
        ]
      },
      "allowedLayers": [
        "pool",
        "house",
        "setter_hatcher",
        "trolley",
        "tray"
      ],
      "fields": [
        {
          "fieldKey": "candlingDay",
          "names": {
            "en": "Candling day",
            "ar": "يوم الفحص"
          },
          "aliases": {
            "en": [
              "candling day",
              "candled age"
            ],
            "ar": [
              "يوم الفحص",
              "عمر التسقيط"
            ]
          },
          "type": "integer",
          "unit": "days",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 21
          },
          "persistence": {
            "localColumn": "candlingDay",
            "remoteColumn": "candling_day"
          }
        },
        {
          "fieldKey": "traySize",
          "names": {
            "en": "Tray size",
            "ar": "حجم الصينية"
          },
          "aliases": {
            "en": [
              "tray size",
              "sample eggs"
            ],
            "ar": [
              "حجم الصينية",
              "عدد البيض"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 500
          },
          "persistence": {
            "localColumn": "traySize",
            "remoteColumn": "tray_size"
          }
        },
        {
          "fieldKey": "infertileCount",
          "names": {
            "en": "Infertile",
            "ar": "غير مخصب"
          },
          "aliases": {
            "en": [
              "infertile",
              "clear eggs"
            ],
            "ar": [
              "غير مخصب",
              "بيض صافي"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "infertileCount",
            "remoteColumn": "infertile_count"
          }
        },
        {
          "fieldKey": "early24hCount",
          "names": {
            "en": "Early dead 24 hours",
            "ar": "نفوق مبكر 24 ساعة"
          },
          "aliases": {
            "en": [
              "24 hour dead",
              "early 24"
            ],
            "ar": [
              "نفوق 24 ساعة",
              "مبكر 24"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "early24hCount",
            "remoteColumn": "early24h_count"
          }
        },
        {
          "fieldKey": "early48hCount",
          "names": {
            "en": "Early dead 48 hours",
            "ar": "نفوق مبكر 48 ساعة"
          },
          "aliases": {
            "en": [
              "48 hour dead",
              "early 48"
            ],
            "ar": [
              "نفوق 48 ساعة",
              "مبكر 48"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "early48hCount",
            "remoteColumn": "early48h_count"
          }
        },
        {
          "fieldKey": "bloodRingCount",
          "names": {
            "en": "Blood ring",
            "ar": "حلقة دموية"
          },
          "aliases": {
            "en": [
              "blood ring"
            ],
            "ar": [
              "حلقة دموية",
              "حلقة الدم"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "bloodRingCount",
            "remoteColumn": "blood_ring_count"
          }
        },
        {
          "fieldKey": "blackEyeCount",
          "names": {
            "en": "Black eye",
            "ar": "العين السوداء"
          },
          "aliases": {
            "en": [
              "black eye"
            ],
            "ar": [
              "العين السوداء"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "blackEyeCount",
            "remoteColumn": "black_eye_count"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "infertilePct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "infertileCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "infertilePct",
            "remoteColumn": "infertile_pct"
          }
        },
        {
          "fieldKey": "early24hPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "early24hCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "early24hPct",
            "remoteColumn": "early24h_pct"
          }
        },
        {
          "fieldKey": "early48hPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "early48hCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "early48hPct",
            "remoteColumn": "early48h_pct"
          }
        },
        {
          "fieldKey": "bloodRingPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "bloodRingCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "bloodRingPct",
            "remoteColumn": "blood_ring_pct"
          }
        },
        {
          "fieldKey": "blackEyePct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "blackEyeCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "blackEyePct",
            "remoteColumn": "black_eye_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "candlingDay",
          "traySize",
          "infertileCount",
          "early24hCount",
          "early48hCount",
          "bloodRingCount",
          "blackEyeCount"
        ]
      },
      "persistence": [
        {
          "localTable": "candled_egg_breakout",
          "remoteTable": "candled_egg_breakout"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house",
          "setter",
          "hatcher",
          "trolley",
          "tray"
        ],
        "measures": [
          "candlingDay",
          "traySize",
          "infertilePct",
          "early24hPct",
          "early48hPct",
          "bloodRingPct",
          "blackEyePct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "hatch_analysis.residue_breakout",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "hatch_analysis_egg_breakouts",
      "moduleKey": "residue_breakout",
      "names": {
        "en": "Hatch Analysis — Residue Breakout",
        "ar": "تحليل الفقس — كسر مخلفات الفقس"
      },
      "aliases": {
        "en": [
          "residue breakout",
          "hatch residue"
        ],
        "ar": [
          "كسر مخلفات الفقس",
          "كسر المتبقي"
        ]
      },
      "allowedLayers": [
        "pool",
        "house",
        "setter_hatcher",
        "trolley",
        "tray"
      ],
      "fields": [
        {
          "fieldKey": "traySize",
          "names": {
            "en": "Tray size",
            "ar": "حجم الصينية"
          },
          "aliases": {
            "en": [
              "tray size",
              "sample eggs"
            ],
            "ar": [
              "حجم الصينية",
              "عدد البيض"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 500
          },
          "persistence": {
            "localColumn": "traySize",
            "remoteColumn": "tray_size"
          }
        },
        {
          "fieldKey": "infertileCount",
          "names": {
            "en": "Infertile",
            "ar": "غير مخصب"
          },
          "aliases": {
            "en": [
              "infertile",
              "clear eggs"
            ],
            "ar": [
              "غير مخصب",
              "بيض صافي"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "infertileCount",
            "remoteColumn": "infertile_count"
          }
        },
        {
          "fieldKey": "earlyDeadCount",
          "names": {
            "en": "Early dead",
            "ar": "نفوق مبكر"
          },
          "aliases": {
            "en": [
              "early dead"
            ],
            "ar": [
              "نفوق مبكر"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "earlyDeadCount",
            "remoteColumn": "early_dead_count"
          }
        },
        {
          "fieldKey": "midDeadCount",
          "names": {
            "en": "Mid dead",
            "ar": "نفوق متوسط"
          },
          "aliases": {
            "en": [
              "mid dead"
            ],
            "ar": [
              "نفوق متوسط"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "midDeadCount",
            "remoteColumn": "mid_dead_count"
          }
        },
        {
          "fieldKey": "lateDeadCount",
          "names": {
            "en": "Late dead",
            "ar": "نفوق متأخر"
          },
          "aliases": {
            "en": [
              "late dead"
            ],
            "ar": [
              "نفوق متأخر"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "lateDeadCount",
            "remoteColumn": "late_dead_count"
          }
        },
        {
          "fieldKey": "externalPipCount",
          "names": {
            "en": "External pip",
            "ar": "نقر خارجي"
          },
          "aliases": {
            "en": [
              "external pip"
            ],
            "ar": [
              "نقر خارجي"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "externalPipCount",
            "remoteColumn": "external_pip_count"
          }
        },
        {
          "fieldKey": "crackedCount",
          "names": {
            "en": "Cracked",
            "ar": "مشقوق"
          },
          "aliases": {
            "en": [
              "cracked"
            ],
            "ar": [
              "مشقوق",
              "بيض مشروخ"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "crackedCount",
            "remoteColumn": "cracked_count"
          }
        },
        {
          "fieldKey": "contaminatedCount",
          "names": {
            "en": "Contaminated",
            "ar": "ملوث"
          },
          "aliases": {
            "en": [
              "contaminated"
            ],
            "ar": [
              "ملوث",
              "بيض ملوث"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "traySize"
          },
          "persistence": {
            "localColumn": "contaminatedCount",
            "remoteColumn": "contaminated_count"
          }
        },
        {
          "fieldKey": "totalEggsSet",
          "names": {
            "en": "Total eggs set",
            "ar": "إجمالي البيض المحضن"
          },
          "aliases": {
            "en": [
              "total eggs set",
              "eggs set"
            ],
            "ar": [
              "إجمالي البيض",
              "البيض المحضن"
            ]
          },
          "type": "integer",
          "unit": "eggs",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 10000000
          },
          "persistence": {
            "localColumn": "totalEggsSet",
            "remoteColumn": "total_eggs_set"
          }
        },
        {
          "fieldKey": "hatchedCount",
          "names": {
            "en": "Hatched chicks",
            "ar": "الكتاكيت الفاقسة"
          },
          "aliases": {
            "en": [
              "hatched",
              "hatched chicks"
            ],
            "ar": [
              "الفاقس",
              "الكتاكيت الفاقسة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "totalEggsSet"
          },
          "persistence": {
            "localColumn": "hatchedCount",
            "remoteColumn": "hatched_count"
          }
        },
        {
          "fieldKey": "culledCount",
          "names": {
            "en": "Culled chicks",
            "ar": "الكتاكيت المستبعدة"
          },
          "aliases": {
            "en": [
              "culled",
              "culled chicks"
            ],
            "ar": [
              "المستبعد",
              "الكتاكيت المستبعدة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "totalEggsSet"
          },
          "persistence": {
            "localColumn": "culledCount",
            "remoteColumn": "culled_count"
          }
        },
        {
          "fieldKey": "deadCount",
          "names": {
            "en": "Dead chicks",
            "ar": "الكتاكيت النافقة"
          },
          "aliases": {
            "en": [
              "dead chicks",
              "dead"
            ],
            "ar": [
              "النافق",
              "الكتاكيت النافقة"
            ]
          },
          "type": "integer",
          "unit": "chicks",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "maxFieldKey": "totalEggsSet"
          },
          "persistence": {
            "localColumn": "deadCount",
            "remoteColumn": "dead_count"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "infertilePct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "infertileCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "infertilePct",
            "remoteColumn": "infertile_pct"
          }
        },
        {
          "fieldKey": "earlyDeadPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "earlyDeadCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "earlyDeadPct",
            "remoteColumn": "early_dead_pct"
          }
        },
        {
          "fieldKey": "midDeadPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "midDeadCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "midDeadPct",
            "remoteColumn": "mid_dead_pct"
          }
        },
        {
          "fieldKey": "lateDeadPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "lateDeadCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "lateDeadPct",
            "remoteColumn": "late_dead_pct"
          }
        },
        {
          "fieldKey": "externalPipPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "externalPipCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "externalPipPct",
            "remoteColumn": "external_pip_pct"
          }
        },
        {
          "fieldKey": "crackedPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "crackedCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "crackedPct",
            "remoteColumn": "cracked_pct"
          }
        },
        {
          "fieldKey": "contaminatedPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "contaminatedCount",
            "traySize"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "contaminatedPct",
            "remoteColumn": "contaminated_pct"
          }
        },
        {
          "fieldKey": "hatchabilityPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "hatchedCount",
            "totalEggsSet"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "hatchabilityPct",
            "remoteColumn": "hatchability_pct"
          }
        },
        {
          "fieldKey": "fertilityPct",
          "kind": "fertility_from_infertile",
          "inputFieldKeys": [
            "traySize",
            "infertileCount"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "fertilityPct",
            "remoteColumn": "fertility_pct"
          }
        },
        {
          "fieldKey": "hofPct",
          "kind": "hof",
          "inputFieldKeys": [
            "hatchabilityPct",
            "fertilityPct"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "hofPct",
            "remoteColumn": "hof_pct"
          }
        },
        {
          "fieldKey": "culledPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "culledCount",
            "totalEggsSet"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "culledPct",
            "remoteColumn": "culled_pct"
          }
        },
        {
          "fieldKey": "deadPct",
          "kind": "percent_of",
          "inputFieldKeys": [
            "deadCount",
            "totalEggsSet"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "deadPct",
            "remoteColumn": "dead_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "traySize",
          "infertileCount",
          "earlyDeadCount",
          "midDeadCount",
          "lateDeadCount",
          "externalPipCount",
          "crackedCount",
          "contaminatedCount",
          "totalEggsSet",
          "hatchedCount",
          "culledCount",
          "deadCount"
        ]
      },
      "persistence": [
        {
          "localTable": "residue_breakout",
          "remoteTable": "residue_breakout"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "house",
          "setter",
          "hatcher",
          "trolley",
          "tray"
        ],
        "measures": [
          "traySize",
          "hatchabilityPct",
          "fertilityPct",
          "hofPct",
          "culledPct",
          "deadPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "setters.environment",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "setters",
      "moduleKey": "environment",
      "names": {
        "en": "Setter — Environment and Settings",
        "ar": "المفرخ — البيئة والإعدادات"
      },
      "aliases": {
        "en": [
          "setter settings",
          "setter environment"
        ],
        "ar": [
          "إعدادات المفرخ",
          "بيئة المفرخ"
        ]
      },
      "allowedLayers": [
        "setter"
      ],
      "fields": [
        {
          "fieldKey": "setpointF",
          "names": {
            "en": "Temperature setpoint",
            "ar": "درجة الحرارة المضبوطة"
          },
          "aliases": {
            "en": [
              "setpoint",
              "temperature setpoint"
            ],
            "ar": [
              "الحرارة المضبوطة",
              "نقطة الضبط"
            ]
          },
          "type": "number",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 80,
            "max": 110
          },
          "persistence": {
            "localColumn": "setpointF",
            "remoteColumn": "setpoint_f"
          }
        },
        {
          "fieldKey": "actualF",
          "names": {
            "en": "Actual temperature",
            "ar": "درجة الحرارة الفعلية"
          },
          "aliases": {
            "en": [
              "actual temperature",
              "actual f"
            ],
            "ar": [
              "الحرارة الفعلية"
            ]
          },
          "type": "number",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 80,
            "max": 110
          },
          "persistence": {
            "localColumn": "actualF",
            "remoteColumn": "actual_f"
          }
        },
        {
          "fieldKey": "setpointRh",
          "names": {
            "en": "Humidity setpoint",
            "ar": "الرطوبة المضبوطة"
          },
          "aliases": {
            "en": [
              "humidity setpoint",
              "setpoint rh"
            ],
            "ar": [
              "الرطوبة المضبوطة"
            ]
          },
          "type": "number",
          "unit": "percent_rh",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 100
          },
          "persistence": {
            "localColumn": "setpointRh",
            "remoteColumn": "setpoint_rh"
          }
        },
        {
          "fieldKey": "actualRh",
          "names": {
            "en": "Actual humidity",
            "ar": "الرطوبة الفعلية"
          },
          "aliases": {
            "en": [
              "actual humidity",
              "actual rh"
            ],
            "ar": [
              "الرطوبة الفعلية"
            ]
          },
          "type": "number",
          "unit": "percent_rh",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 100
          },
          "persistence": {
            "localColumn": "actualRh",
            "remoteColumn": "actual_rh"
          }
        },
        {
          "fieldKey": "turningAngle",
          "names": {
            "en": "Turning angle",
            "ar": "زاوية التقليب"
          },
          "aliases": {
            "en": [
              "turning angle",
              "turn angle"
            ],
            "ar": [
              "زاوية التقليب"
            ]
          },
          "type": "number",
          "unit": "degrees",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 90
          },
          "persistence": {
            "localColumn": "turningAngle",
            "remoteColumn": "turning_angle"
          }
        },
        {
          "fieldKey": "co2Ppm",
          "names": {
            "en": "CO2",
            "ar": "ثاني أكسيد الكربون"
          },
          "aliases": {
            "en": [
              "co2",
              "carbon dioxide"
            ],
            "ar": [
              "ثاني أكسيد الكربون",
              "سي او تو"
            ]
          },
          "type": "number",
          "unit": "ppm",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 10000
          },
          "persistence": {
            "localColumn": "co2Ppm",
            "remoteColumn": "co2_ppm"
          }
        },
        {
          "fieldKey": "incubationAgeDays",
          "names": {
            "en": "Incubation age",
            "ar": "عمر التحضين"
          },
          "aliases": {
            "en": [
              "incubation age",
              "incubation day"
            ],
            "ar": [
              "عمر التحضين",
              "يوم التحضين"
            ]
          },
          "type": "integer",
          "unit": "days",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 21
          },
          "persistence": {
            "localColumn": "incubationAgeDays",
            "remoteColumn": "incubation_age_days"
          }
        },
        {
          "fieldKey": "incubationHours",
          "names": {
            "en": "Incubation hours",
            "ar": "ساعات التحضين"
          },
          "aliases": {
            "en": [
              "incubation hours",
              "hours"
            ],
            "ar": [
              "ساعات التحضين"
            ]
          },
          "type": "integer",
          "unit": "hours",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 23
          },
          "persistence": {
            "localColumn": "incubationHours",
            "remoteColumn": "incubation_hours"
          }
        }
      ],
      "calculations": [],
      "completion": {
        "requiredFieldKeys": [
          "setpointF",
          "actualF",
          "setpointRh",
          "actualRh",
          "turningAngle",
          "co2Ppm",
          "incubationAgeDays",
          "incubationHours"
        ]
      },
      "persistence": [
        {
          "localTable": "setter_optimizing",
          "remoteTable": "setter_optimizing"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter"
        ],
        "measures": [
          "setpointF",
          "actualF",
          "setpointRh",
          "actualRh",
          "turningAngle",
          "co2Ppm"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "setters.shell_temperature",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "setters",
      "moduleKey": "shell_temperature",
      "names": {
        "en": "Setter — Shell Temperature",
        "ar": "المفرخ — حرارة القشرة"
      },
      "aliases": {
        "en": [
          "setter est",
          "setter shell temperature"
        ],
        "ar": [
          "حرارة القشرة بالمفرخ",
          "قراءات حرارة القشرة"
        ]
      },
      "allowedLayers": [
        "setter"
      ],
      "fields": [
        {
          "fieldKey": "estReadingsJson",
          "names": {
            "en": "Shell temperature readings",
            "ar": "قراءات حرارة القشرة"
          },
          "aliases": {
            "en": [
              "est readings",
              "shell temperatures"
            ],
            "ar": [
              "قراءات الحرارة",
              "حرارة القشرة"
            ]
          },
          "type": "number_list",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 80,
            "itemMax": 110
          },
          "persistence": {
            "localColumn": "estReadingsJson",
            "remoteColumn": "est_readings_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "estSampleSize",
          "kind": "series_sample_size",
          "inputFieldKeys": [
            "estReadingsJson"
          ],
          "unit": "eggs",
          "persistence": {
            "localColumn": "estSampleSize",
            "remoteColumn": "est_sample_size"
          }
        },
        {
          "fieldKey": "estAvg",
          "kind": "series_average",
          "inputFieldKeys": [
            "estReadingsJson"
          ],
          "unit": "fahrenheit",
          "persistence": {
            "localColumn": "estAvg",
            "remoteColumn": "est_avg"
          }
        },
        {
          "fieldKey": "estCvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "estReadingsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "estCvPct",
            "remoteColumn": "est_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "estReadingsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "setter_optimizing",
          "remoteTable": "setter_optimizing"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "setter"
        ],
        "measures": [
          "incubationAgeDays",
          "incubationHours",
          "estSampleSize",
          "estAvg",
          "estCvPct"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "hatchers.environment",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "hatchers",
      "moduleKey": "environment",
      "names": {
        "en": "Hatcher — Environment and Settings",
        "ar": "الفقاسة — البيئة والإعدادات"
      },
      "aliases": {
        "en": [
          "hatcher settings",
          "hatcher environment"
        ],
        "ar": [
          "إعدادات الفقاسة",
          "بيئة الفقاسة"
        ]
      },
      "allowedLayers": [
        "hatcher"
      ],
      "fields": [
        {
          "fieldKey": "setpointF",
          "names": {
            "en": "Temperature setpoint",
            "ar": "درجة الحرارة المضبوطة"
          },
          "aliases": {
            "en": [
              "setpoint",
              "temperature setpoint"
            ],
            "ar": [
              "الحرارة المضبوطة",
              "نقطة الضبط"
            ]
          },
          "type": "number",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 80,
            "max": 110
          },
          "persistence": {
            "localColumn": "setpointF",
            "remoteColumn": "setpoint_f"
          }
        },
        {
          "fieldKey": "setpointRh",
          "names": {
            "en": "Humidity setpoint",
            "ar": "الرطوبة المضبوطة"
          },
          "aliases": {
            "en": [
              "humidity setpoint",
              "setpoint rh"
            ],
            "ar": [
              "الرطوبة المضبوطة"
            ]
          },
          "type": "number",
          "unit": "percent_rh",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 100
          },
          "persistence": {
            "localColumn": "setpointRh",
            "remoteColumn": "setpoint_rh"
          }
        },
        {
          "fieldKey": "incubationAgeDays",
          "names": {
            "en": "Incubation age",
            "ar": "عمر التحضين"
          },
          "aliases": {
            "en": [
              "incubation age",
              "incubation day"
            ],
            "ar": [
              "عمر التحضين",
              "يوم التحضين"
            ]
          },
          "type": "integer",
          "unit": "days",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 21
          },
          "persistence": {
            "localColumn": "incubationAgeDays",
            "remoteColumn": "incubation_age_days"
          }
        },
        {
          "fieldKey": "incubationHours",
          "names": {
            "en": "Incubation hours",
            "ar": "ساعات التحضين"
          },
          "aliases": {
            "en": [
              "incubation hours",
              "hours"
            ],
            "ar": [
              "ساعات التحضين"
            ]
          },
          "type": "integer",
          "unit": "hours",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 23
          },
          "persistence": {
            "localColumn": "incubationHours",
            "remoteColumn": "incubation_hours"
          }
        },
        {
          "fieldKey": "co2Ppm",
          "names": {
            "en": "CO2",
            "ar": "ثاني أكسيد الكربون"
          },
          "aliases": {
            "en": [
              "co2",
              "carbon dioxide"
            ],
            "ar": [
              "ثاني أكسيد الكربون",
              "سي او تو"
            ]
          },
          "type": "number",
          "unit": "ppm",
          "required": true,
          "explicitZero": true,
          "validation": {
            "min": 0,
            "max": 10000
          },
          "persistence": {
            "localColumn": "co2Ppm",
            "remoteColumn": "co2_ppm"
          }
        },
        {
          "fieldKey": "chickPanting",
          "names": {
            "en": "Chick panting",
            "ar": "لهاث الكتاكيت"
          },
          "aliases": {
            "en": [
              "panting",
              "chick panting"
            ],
            "ar": [
              "لهاث",
              "لهاث الكتاكيت"
            ]
          },
          "type": "boolean",
          "unit": "boolean",
          "required": true,
          "explicitZero": false,
          "validation": {},
          "persistence": {
            "localColumn": "chickPanting",
            "remoteColumn": "chick_panting",
            "encoding": "integer_boolean"
          }
        },
        {
          "fieldKey": "meconium",
          "names": {
            "en": "Meconium",
            "ar": "العقي"
          },
          "aliases": {
            "en": [
              "meconium"
            ],
            "ar": [
              "العقي",
              "ميكونيوم"
            ]
          },
          "type": "string",
          "unit": "status",
          "required": true,
          "explicitZero": false,
          "validation": {
            "choices": [
              "none",
              "light",
              "heavy"
            ]
          },
          "persistence": {
            "localColumn": "meconium",
            "remoteColumn": "meconium"
          }
        },
        {
          "fieldKey": "transferDay",
          "names": {
            "en": "Transfer day",
            "ar": "يوم النقل"
          },
          "aliases": {
            "en": [
              "transfer day"
            ],
            "ar": [
              "يوم النقل"
            ]
          },
          "type": "integer",
          "unit": "days",
          "required": true,
          "explicitZero": false,
          "validation": {
            "min": 1,
            "max": 21
          },
          "persistence": {
            "localColumn": "transferDay",
            "remoteColumn": "transfer_day"
          }
        }
      ],
      "calculations": [],
      "completion": {
        "requiredFieldKeys": [
          "setpointF",
          "setpointRh",
          "incubationAgeDays",
          "incubationHours",
          "co2Ppm",
          "chickPanting",
          "meconium",
          "transferDay"
        ]
      },
      "persistence": [
        {
          "localTable": "hatcher_optimizing",
          "remoteTable": "hatcher_optimizing"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "hatcher"
        ],
        "measures": [
          "setpointF",
          "setpointRh",
          "co2Ppm",
          "chickPanting",
          "meconium",
          "transferDay"
        ]
      },
      "warnings": []
    },
    {
      "schemaKey": "hatchers.cvt",
      "version": 1,
      "sectorKeys": [
        "breeder"
      ],
      "stationKey": "hatchers",
      "moduleKey": "cvt",
      "names": {
        "en": "Hatcher — Chick Vent Temperature",
        "ar": "الفقاسة — حرارة مخرج الكتكوت"
      },
      "aliases": {
        "en": [
          "hatcher cvt",
          "hatcher vent temperature"
        ],
        "ar": [
          "حرارة الكتاكيت بالفقاسة",
          "حرارة المخرج"
        ]
      },
      "allowedLayers": [
        "hatcher"
      ],
      "fields": [
        {
          "fieldKey": "cvtReadingsJson",
          "names": {
            "en": "Vent temperature readings",
            "ar": "قراءات حرارة المخرج"
          },
          "aliases": {
            "en": [
              "cvt readings",
              "vent temperatures"
            ],
            "ar": [
              "قراءات حرارة المخرج",
              "درجات حرارة الكتاكيت"
            ]
          },
          "type": "number_list",
          "unit": "fahrenheit",
          "required": true,
          "explicitZero": false,
          "validation": {
            "minItems": 1,
            "itemMin": 80,
            "itemMax": 110
          },
          "persistence": {
            "localColumn": "cvtReadingsJson",
            "remoteColumn": "cvt_readings_json"
          }
        }
      ],
      "calculations": [
        {
          "fieldKey": "cvtSampleSize",
          "kind": "series_sample_size",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "chicks",
          "persistence": {
            "localColumn": "cvtSampleSize",
            "remoteColumn": "cvt_sample_size"
          }
        },
        {
          "fieldKey": "cvtAvg",
          "kind": "series_average",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "fahrenheit",
          "persistence": {
            "localColumn": "cvtAvg",
            "remoteColumn": "cvt_avg"
          }
        },
        {
          "fieldKey": "cvtCvPct",
          "kind": "series_cv",
          "inputFieldKeys": [
            "cvtReadingsJson"
          ],
          "unit": "percent",
          "persistence": {
            "localColumn": "cvtCvPct",
            "remoteColumn": "cvt_cv_pct"
          }
        }
      ],
      "completion": {
        "requiredFieldKeys": [
          "cvtReadingsJson"
        ]
      },
      "persistence": [
        {
          "localTable": "hatcher_optimizing",
          "remoteTable": "hatcher_optimizing"
        }
      ],
      "read": {
        "dimensions": [
          "date",
          "hatcher"
        ],
        "measures": [
          "cvtSampleSize",
          "cvtAvg",
          "cvtCvPct"
        ]
      },
      "warnings": []
    }
  ]
} as const

export function requireStationSchema(
  schemaKey: string,
  version: number,
): AgentStationSchema {
  const schema = agentStationRegistry.stations.find((candidate) =>
    candidate.schemaKey === schemaKey && candidate.version === version
  )
  if (!schema) throw new Error('Unknown station schema')
  return schema
}

export function applicableStationSchemas(
  sectorKeys: readonly string[],
): readonly AgentStationSchema[] {
  const allowed = new Set(sectorKeys)
  return agentStationRegistry.stations.filter((schema) =>
    schema.sectorKeys.some((sectorKey) => allowed.has(sectorKey))
  )
}
