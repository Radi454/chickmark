const Map<String, Map<String, dynamic>> kTroubleshootingSeeds = {
  'pasgar_final_score': {
    'hatcheryCauses': {
      'Equipment': [
        'Incorrect chick box ventilation during holding.',
        'Uneven hatcher temperature reducing chick vigor.',
      ],
      'Management': [
        'Late pull timing causing dehydration.',
        'Rough handling during processing or transfer.',
      ],
    },
    'farmFlockCauses': {
      'Flock Health': [
        'Poor breeder health reducing chick quality.',
        'High contamination pressure affecting embryo development.',
      ],
      'Nutrition': [
        'Breeder vitamin or trace mineral imbalance.',
        'Poor shell-quality support in the breeder ration.',
      ],
    },
  },
  'chick_cv': {
    'hatcheryCauses': {
      'Equipment': [
        'Uneven machine temperature or airflow across baskets.',
        'Poor calibration between setter zones.',
      ],
      'Management': [
        'Mixed egg sizes set together without compensation.',
        'Wide collection or storage variation before set.',
      ],
    },
    'farmFlockCauses': {
      'Flock Uniformity': [
        'Poor breeder body-weight uniformity driving egg-size spread.',
        'Mixed-age eggs combined in the same flock lot.',
      ],
      'Egg Handling': [
        'Inconsistent egg selection at the farm.',
        'Variable storage duration before transport.',
      ],
    },
  },
  'yfbm': {
    'hatcheryCauses': {
      'Equipment': [
        'Temperature profile too cool late in incubation.',
        'Inconsistent transfer timing across machines.',
      ],
      'Management': [
        'Embryos pulled before full yolk utilization.',
        'Excessive storage age reducing yolk absorption.',
      ],
    },
    'farmFlockCauses': {
      'Breeder Factors': [
        'Breeder age effect on yolk utilization.',
        'Poor egg-size consistency from the flock.',
      ],
      'Nutrition': [
        'Imbalanced breeder energy or fatty-acid profile.',
        'Micronutrient deficiency affecting embryo development.',
      ],
    },
  },
  'cvt_avg': {
    'hatcheryCauses': {
      'Equipment': [
        'Hot or cold spots in the hatcher.',
        'Incorrect machine setpoint or poor probe calibration.',
      ],
      'Management': [
        'Pulling chicks too early or too late.',
        'Overloaded baskets reducing uniform ventilation.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Inconsistent shell conductance across the flock.',
        'Embryo vitality differences due to breeder condition.',
      ],
      'Handling': [
        'Large variation in egg storage duration before set.',
        'Poor preheating consistency before incubation.',
      ],
    },
  },
  'cha_co2': {
    'hatcheryCauses': {
      'Ventilation': [
        'Insufficient fresh-air exchange in the chick room.',
        'Blocked inlets or poorly balanced exhaust fans.',
      ],
      'Management': [
        'Too many chick boxes staged in a confined area.',
        'Delayed dispatch increasing room occupancy time.',
      ],
    },
    'farmFlockCauses': {
      'Planning': [
        'Irregular placement scheduling causing processing congestion.',
        'Large flock pulls arriving without space planning.',
      ],
      'Transport': [
        'Slow truck turnaround extending hatchery holding time.',
        'Late farm acceptance extending waiting time.',
      ],
    },
  },
  'cha_pm10': {
    'hatcheryCauses': {
      'Housekeeping': [
        'Dust buildup in filters, ducts, or processing lines.',
        'Inadequate cleaning routine between pulls.',
      ],
      'Ventilation': [
        'Poor extraction around chick handling points.',
        'Insufficient pressure control drawing in dust.',
      ],
    },
    'farmFlockCauses': {
      'Source Load': [
        'Dirty egg trays or transport equipment entering the hatchery.',
        'High shell dust from poor farm egg handling.',
      ],
      'Biosecurity': [
        'Returnables not cleaned effectively between farms.',
        'Dust transfer from contaminated service vehicles.',
      ],
    },
  },
  'cha_pm25': {
    'hatcheryCauses': {
      'Ventilation': [
        'Fine-particle filtration is inadequate for the room load.',
        'Air recirculation is too high for processing volume.',
      ],
      'Housekeeping': [
        'Compressed-air cleaning redistributing fine dust.',
        'High traffic stirring residual particulates.',
      ],
    },
    'farmFlockCauses': {
      'Source Load': [
        'Poor tray cleanliness contributing fine dust.',
        'Excess shell debris from cracked or dirty eggs.',
      ],
      'Operations': [
        'Farm return equipment not cleaned before reuse.',
        'Vehicle airflow carrying dust into clean areas.',
      ],
    },
  },
  'cha_air_velocity': {
    'hatcheryCauses': {
      'Ventilation': [
        'Poorly balanced inlets and outlets at chick level.',
        'Fan drift or blocked louvers.',
      ],
      'Layout': [
        'Box stacks obstructing air paths.',
        'Room layout creating dead zones around holding areas.',
      ],
    },
    'farmFlockCauses': {
      'Logistics': [
        'Dispatch staging plan creating overcrowded holding lanes.',
        'Returnable equipment stored in airflow paths.',
      ],
      'Timing': [
        'Late loading causing prolonged chick holding.',
        'Uneven truck arrival windows disrupting room flow.',
      ],
    },
  },
  'cha_noise': {
    'hatcheryCauses': {
      'Equipment': [
        'Worn fan bearings or mechanical vibration.',
        'Unbalanced motors or loose duct panels.',
      ],
      'Management': [
        'Simultaneous equipment operation without zoning.',
        'Excessive traffic or rough handling in the processing area.',
      ],
    },
    'farmFlockCauses': {
      'Planning': [
        'Congested loading windows increasing noise exposure.',
        'Poor dock coordination keeping chicks in noisy zones longer.',
      ],
      'Transport': [
        'Improper crate handling during collection and dispatch.',
        'Vehicles idling near chick holding areas.',
      ],
    },
  },
  'ha_hatchability': {
    'hatcheryCauses': {
      'Incubation': [
        'Incorrect setter or hatcher temperature profile.',
        'Poor humidity control during incubation.',
      ],
      'Management': [
        'Suboptimal egg storage time before setting.',
        'Delayed transfer or pull timing.',
      ],
    },
    'farmFlockCauses': {
      'Fertility': [
        'Low male fertility in the breeder flock.',
        'Improper mating ratio or poor male condition.',
      ],
      'Egg Quality': [
        'Poor shell quality or contamination from the farm.',
        'High floor-egg percentage reducing set quality.',
      ],
    },
  },
  'ha_fertility': {
    'hatcheryCauses': {
      'Records': [
        'Breakout classification is inconsistent.',
        'Poor sample handling masking true infertility.',
      ],
      'Handling': [
        'Storage damage obscuring embryo signs.',
        'Excessive egg jarring during transport or set.',
      ],
    },
    'farmFlockCauses': {
      'Male Management': [
        'Low male body weight, libido, or mating activity.',
        'Insufficient male replacement or poor distribution.',
      ],
      'Breeder Health': [
        'Disease challenge reducing reproductive performance.',
        'Nutritional deficiency affecting fertility.',
      ],
    },
  },
  'ha_hof': {
    'hatcheryCauses': {
      'Incubation': [
        'Overheating during late incubation.',
        'Poor ventilation in the hatcher.',
      ],
      'Management': [
        'Excessive storage age reducing embryo viability.',
        'Improper sanitation increasing contamination losses.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Micro-cracks or poor shell integrity from the flock.',
        'Dirty nest conditions causing bacterial contamination.',
      ],
      'Breeder Health': [
        'Poor breeder livability or stress affecting embryo quality.',
        'Nutrient deficiencies affecting hatch of fertile eggs.',
      ],
    },
  },
  'eb_infertile': {
    'hatcheryCauses': {
      'Classification': [
        'Early dead embryos misclassified as infertile.',
        'Poor breakout lighting or technician inconsistency.',
      ],
      'Handling': [
        'Storage damage obscuring embryo signs.',
        'Excessive transport vibration before set.',
      ],
    },
    'farmFlockCauses': {
      'Male Management': [
        'Poor male fertility or insufficient mating activity.',
        'Incorrect male-to-female ratio.',
      ],
      'Breeder Health': [
        'Age-related fertility decline.',
        'Vitamin E or selenium imbalance.',
      ],
    },
  },
  'eb_early_dead': {
    'hatcheryCauses': {
      'Sanitation': [
        'High bacterial load on eggs or equipment.',
        'Improper fumigation or sanitation routine.',
      ],
      'Incubation': [
        'Incorrect start temperature or preheat process.',
        'Excessive egg storage before set.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Dirty eggs or shell damage from collection.',
        'Improper farm cooling before transport.',
      ],
      'Nutrition': [
        'Breeder micronutrient deficiency affecting embryo survival.',
        'Poor breeder body condition.',
      ],
    },
  },
  'eb_mid_dead': {
    'hatcheryCauses': {
      'Incubation': [
        'Setter temperature drift during organ development.',
        'Poor airflow through egg packs.',
      ],
      'Management': [
        'Mixed egg sizes creating uneven embryo demand.',
        'Inconsistent turning performance.',
      ],
    },
    'farmFlockCauses': {
      'Breeder Health': [
        'Chronic flock stress or disease pressure.',
        'Egg nutrient quality not supporting embryo growth.',
      ],
      'Handling': [
        'Long transport times without stable conditions.',
        'Repeated temperature cycling before set.',
      ],
    },
  },
  'eb_late_dead': {
    'hatcheryCauses': {
      'Hatcher Conditions': [
        'Poor late-incubation ventilation or CO2 control.',
        'Excessive machine temperature near hatch.',
      ],
      'Management': [
        'Transfer timing error.',
        'Incorrect hatch window management.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Poor shell conductance limiting gas exchange.',
        'Large egg-size variation late in breeder life.',
      ],
      'Breeder Factors': [
        'Older flock embryo vitality decline.',
        'Suboptimal breeder nutrition affecting hatchability.',
      ],
    },
  },
  'eb_internal_pip': {
    'hatcheryCauses': {
      'Ventilation': [
        'High CO2 or inadequate oxygen near hatch.',
        'Poor airflow through baskets during pipping.',
      ],
      'Humidity': [
        'Humidity profile delaying membrane drying.',
        'Incorrect moisture loss during incubation.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Shell quality limiting gas exchange.',
        'Egg age or storage affecting membrane quality.',
      ],
      'Breeder Factors': [
        'Embryo weakness from poor breeder nutrition.',
        'Flock age increasing late-hatch variation.',
      ],
    },
  },
  'eb_external_pip': {
    'hatcheryCauses': {
      'Hatcher Management': [
        'Chicks unable to complete hatch due to poor humidity.',
        'Excessive temperature during final hatch stages.',
      ],
      'Ventilation': [
        'Inadequate oxygen availability in the hatcher.',
        'Poor air movement around pipping baskets.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Weak shell or membrane quality.',
        'Contamination affecting chick strength at hatch.',
      ],
      'Breeder Nutrition': [
        'Nutrient imbalance reducing chick vigor.',
        'Poor mineral support affecting shell quality.',
      ],
    },
  },
  'eb_cracked': {
    'hatcheryCauses': {
      'Handling': [
        'Rough tray transfer or stacking in the hatchery.',
        'Improper equipment setup causing shell damage.',
      ],
      'Transport': [
        'Excess vibration or drop events during internal movement.',
        'Overfilled trays or unstable racks.',
      ],
    },
    'farmFlockCauses': {
      'Collection': [
        'Poor egg collection technique.',
        'Inadequate nest management increasing shell damage.',
      ],
      'Shell Quality': [
        'Thin shells from mineral imbalance or flock age.',
        'Poor shell texture increasing breakage risk.',
      ],
    },
  },
  'eb_contaminated': {
    'hatcheryCauses': {
      'Sanitation': [
        'Inadequate equipment disinfection between sets.',
        'Poor hygiene during transfer and breakout.',
      ],
      'Handling': [
        'Dirty trays or chick-box contact surfaces.',
        'Cross-contamination from personnel or tools.',
      ],
    },
    'farmFlockCauses': {
      'Nest Hygiene': [
        'Dirty litter or nest boxes contaminating eggs.',
        'High floor-egg percentage entering the set.',
      ],
      'Collection': [
        'Delayed egg collection allowing contamination to persist.',
        'Improper farm egg sanitizing practices.',
      ],
    },
  },
  'eb_malposition': {
    'hatcheryCauses': {
      'Turning': [
        'Incorrect egg turning angle or frequency.',
        'Egg orientation errors during set or transfer.',
      ],
      'Incubation': [
        'Uneven incubation affecting embryo alignment.',
        'Poor late-incubation temperature control.',
      ],
    },
    'farmFlockCauses': {
      'Egg Shape': [
        'Abnormal egg shape increasing malposition risk.',
        'Very large or small eggs in the same lot.',
      ],
      'Breeder Factors': [
        'Older flock shell-quality issues.',
        'Nutritional imbalance affecting egg formation.',
      ],
    },
  },
  'eb_exposed_brain': {
    'hatcheryCauses': {
      'Incubation': [
        'Severe overheating during embryo development.',
        'Critical humidity control errors.',
      ],
      'Handling': [
        'Misclassification of severe developmental abnormalities.',
        'Poor sampling quality during breakout.',
      ],
    },
    'farmFlockCauses': {
      'Breeder Health': [
        'Severe breeder nutritional imbalance.',
        'Toxin or disease exposure affecting embryo development.',
      ],
      'Egg Quality': [
        'Poor shell conductance or severe contamination.',
        'Egg storage abuse before incubation.',
      ],
    },
  },
  'eb_crossed_beak': {
    'hatcheryCauses': {
      'Incubation': [
        'Temperature extremes during critical development.',
        'Uneven machine conditions across trays.',
      ],
      'Classification': [
        'Inconsistent breakout coding of deformities.',
        'Small sample size exaggerating abnormality rate.',
      ],
    },
    'farmFlockCauses': {
      'Breeder Nutrition': [
        'Vitamin or mineral deficiency affecting development.',
        'Poor trace mineral balance in the breeder diet.',
      ],
      'Breeder Health': [
        'Disease or toxin challenge during egg production.',
        'Genetic or age-related increase in abnormalities.',
      ],
    },
  },
  'eb_culled_dead': {
    'hatcheryCauses': {
      'Processing': [
        'Rough handling during pull or processing.',
        'Delayed access to comfort after hatch.',
      ],
      'Hatcher Conditions': [
        'Overheating, dehydration, or poor ventilation at pull.',
        'Extended hatch window producing weak chicks.',
      ],
    },
    'farmFlockCauses': {
      'Breeder Quality': [
        'Poor breeder nutrition reducing chick vitality.',
        'Low-quality eggs from stressed or old flocks.',
      ],
      'Egg Handling': [
        'Storage abuse reducing chick resilience at hatch.',
        'Contamination increasing weak-chick incidence.',
      ],
    },
  },
  'es_shell_temp': {
    'hatcheryCauses': {
      'Environment': [
        'Egg room temperature set too high or too low.',
        'Poor airflow around stored trays.',
      ],
      'Management': [
        'Stacking pattern causing uneven shell temperature.',
        'Frequent door opening creating fluctuations.',
      ],
    },
    'farmFlockCauses': {
      'Transport': [
        'Eggs arriving warmer than target from the farm.',
        'Poor truck temperature control before storage.',
      ],
      'Collection': [
        'Eggs not cooled consistently after collection.',
        'Variable egg age entering storage.',
      ],
    },
  },
  'es_turning_times': {
    'hatcheryCauses': {
      'Equipment': [
        'Turning system not operating on schedule.',
        'Controller or timer drift in the storage room.',
      ],
      'Management': [
        'Turning SOP not followed consistently.',
        'Missed turns during busy operational periods.',
      ],
    },
    'farmFlockCauses': {
      'Transport': [
        'Eggs arriving after long static holding without movement.',
        'Return equipment not supporting stable tray handling.',
      ],
      'Operations': [
        'Farm and hatchery storage practices are not aligned.',
        'Collection schedule causing irregular holding times.',
      ],
    },
  },
  'es_egg_uniformity': {
    'hatcheryCauses': {
      'Selection': [
        'Mixed egg sizes stored together without grading.',
        'Insufficient rejection of outlier eggs before storage.',
      ],
      'Handling': [
        'Uneven storage age within the same batch.',
        'Poor lot segregation during receiving.',
      ],
    },
    'farmFlockCauses': {
      'Flock Uniformity': [
        'Poor breeder body-weight uniformity causing egg-size spread.',
        'Mixed-age eggs combined during collection.',
      ],
      'Nutrition': [
        'Inconsistent flock feed intake affecting egg size.',
        'Poor mineral support reducing shell consistency.',
      ],
    },
  },
  'so_co2': {
    'hatcheryCauses': {
      'Ventilation': [
        'Setter room fresh-air supply is inadequate.',
        'CO2 extraction is not balanced across the room.',
      ],
      'Management': [
        'High occupancy of nearby equipment or egg loads.',
        'Doors left closed too long without purge cycles.',
      ],
    },
    'farmFlockCauses': {
      'Planning': [
        'Large egg deliveries creating temporary congestion.',
        'Poor receiving flow causing prolonged staging.',
      ],
      'Transport': [
        'Late arrivals compressing storage and set preparation time.',
        'Improper pre-set holding conditions during transport.',
      ],
    },
  },
  'so_est_avg': {
    'hatcheryCauses': {
      'Setter Conditions': [
        'Setter temperature profile not aligned to embryo heat output.',
        'Airflow inconsistency between setter zones.',
      ],
      'Management': [
        'Egg size mix not accounted for in set strategy.',
        'Inadequate calibration of handheld EST readings.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Large shell-quality differences across the flock.',
        'Variable egg weight driving different heating rates.',
      ],
      'Breeder Factors': [
        'Breeder age creating inconsistent embryo heat production.',
        'Nutritional imbalance affecting shell conductance.',
      ],
    },
  },
  'ho_co2': {
    'hatcheryCauses': {
      'Ventilation': [
        'Hatcher room extraction is insufficient.',
        'CO2 removal is poor during peak hatch activity.',
      ],
      'Management': [
        'Too many baskets staged without enough air turnover.',
        'Machine loading pattern blocking airflow.',
      ],
    },
    'farmFlockCauses': {
      'Logistics': [
        'Late truck arrival extending chick holding time.',
        'Placement delays causing prolonged room occupancy.',
      ],
      'Planning': [
        'Poor hatch dispatch scheduling.',
        'Overlapping flock processing windows.',
      ],
    },
  },
  'ho_cvt_avg': {
    'hatcheryCauses': {
      'Hatcher Conditions': [
        'Machine setpoint or probe calibration is incorrect.',
        'Basket placement creates hot or cold spots.',
      ],
      'Management': [
        'Chicks held too long before pull.',
        'Uneven hatch window not managed correctly.',
      ],
    },
    'farmFlockCauses': {
      'Egg Quality': [
        'Embryo development variation from breeder age or egg size.',
        'Storage variation affecting hatch timing.',
      ],
      'Breeder Factors': [
        'Poor flock uniformity leading to uneven heat production.',
        'Breeder health affecting chick vigor at hatch.',
      ],
    },
  },
  'ho_chick_panting': {
    'hatcheryCauses': {
      'Environment': [
        'Chick holding area is too warm or poorly ventilated.',
        'High CO2 or low air speed around chick boxes.',
      ],
      'Management': [
        'Delayed dispatch causing thermal stress.',
        'Overcrowded boxes increasing heat load.',
      ],
    },
    'farmFlockCauses': {
      'Logistics': [
        'Placement delays increasing chick holding time.',
        'Transport plan is not ready at hatch pull.',
      ],
      'Transport': [
        'Truck climate control is inadequate.',
        'Loading pattern restricts airflow around boxes.',
      ],
    },
  },
};
