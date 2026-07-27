export interface TelegramFileDownload {
  fileData: string
  mimeType: string
}

type FetchLike = typeof fetch

export async function sendTelegramMessage(params: {
  botToken: string
  chatId: string
  text: string
  fetchImpl?: FetchLike
}): Promise<void> {
  const response = await (params.fetchImpl ?? fetch)(
    `https://api.telegram.org/bot${params.botToken}/sendMessage`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: params.chatId, text: params.text }),
    },
  )
  if (!response.ok) {
    throw new Error(`Telegram sendMessage failed: ${response.status}`)
  }
}

export async function downloadTelegramFile(params: {
  botToken: string
  fileId: string
  fallbackMimeType: string
  fetchImpl?: FetchLike
}): Promise<TelegramFileDownload> {
  const fetchImpl = params.fetchImpl ?? fetch
  const metadataResponse = await fetchImpl(
    `https://api.telegram.org/bot${params.botToken}/getFile?file_id=${
      encodeURIComponent(params.fileId)
    }`,
  )
  if (!metadataResponse.ok) {
    throw new Error(`Telegram getFile failed: ${metadataResponse.status}`)
  }

  const metadata = await metadataResponse.json() as {
    ok?: boolean
    result?: { file_path?: string }
  }
  const filePath = metadata.ok ? metadata.result?.file_path : null
  if (!filePath) {
    throw new Error('Telegram getFile returned no file path')
  }

  const fileResponse = await fetchImpl(
    `https://api.telegram.org/file/bot${params.botToken}/${filePath}`,
  )
  if (!fileResponse.ok) {
    throw new Error(`Telegram file download failed: ${fileResponse.status}`)
  }

  const mimeType = fileResponse.headers.get('Content-Type')?.split(';')[0] ||
    params.fallbackMimeType
  const bytes = new Uint8Array(await fileResponse.arrayBuffer())
  return {
    fileData: `data:${mimeType};base64,${encodeBase64(bytes)}`,
    mimeType,
  }
}

function encodeBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000
  let binary = ''
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize))
  }
  return btoa(binary)
}
