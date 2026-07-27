export interface ExtractedHatcheryRow {
  rowOrdinal: number
  customerName: string | null
  flockName: string | null
  stationName: string | null
  breed: string | null
  eggsPlaced: number | null
  productionDate: string | null
  placementDate: string | null
  eggWeightG: number | null
  fertilityPct: number | null
  transferWeightG: number | null
  setterNumber: string | null
  hatcherNumber: string | null
  hatchDate: string | null
  healthyChicks: number | null
  secondGradeChicks: number | null
  condemnedChicks: number | null
  totalProduction: number | null
  confidencePct: number
}

export interface MissingQuestion {
  rowOrdinal: number | null
  fieldKey: string
  questionTextEn: string
  questionTextAr: string
}

export interface HatcheryExtraction {
  rows: ExtractedHatcheryRow[]
  missingQuestions: MissingQuestion[]
}

export const hatcheryExtractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['rows', 'missingQuestions'],
  properties: {
    rows: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'rowOrdinal',
          'customerName',
          'flockName',
          'stationName',
          'breed',
          'eggsPlaced',
          'productionDate',
          'placementDate',
          'eggWeightG',
          'fertilityPct',
          'transferWeightG',
          'setterNumber',
          'hatcherNumber',
          'hatchDate',
          'healthyChicks',
          'secondGradeChicks',
          'condemnedChicks',
          'totalProduction',
          'confidencePct',
        ],
        properties: {
          rowOrdinal: { type: 'integer' },
          customerName: { type: ['string', 'null'] },
          flockName: { type: ['string', 'null'] },
          stationName: { type: ['string', 'null'] },
          breed: { type: ['string', 'null'] },
          eggsPlaced: { type: ['integer', 'null'] },
          productionDate: { type: ['string', 'null'] },
          placementDate: { type: ['string', 'null'] },
          eggWeightG: { type: ['number', 'null'] },
          fertilityPct: { type: ['number', 'null'] },
          transferWeightG: { type: ['number', 'null'] },
          setterNumber: { type: ['string', 'null'] },
          hatcherNumber: { type: ['string', 'null'] },
          hatchDate: { type: ['string', 'null'] },
          healthyChicks: { type: ['integer', 'null'] },
          secondGradeChicks: { type: ['integer', 'null'] },
          condemnedChicks: { type: ['integer', 'null'] },
          totalProduction: { type: ['integer', 'null'] },
          confidencePct: { type: 'number' },
        },
      },
    },
    missingQuestions: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'rowOrdinal',
          'fieldKey',
          'questionTextEn',
          'questionTextAr',
        ],
        properties: {
          rowOrdinal: { type: ['integer', 'null'] },
          fieldKey: { type: 'string' },
          questionTextEn: { type: 'string' },
          questionTextAr: { type: 'string' },
        },
      },
    },
  },
} as const
