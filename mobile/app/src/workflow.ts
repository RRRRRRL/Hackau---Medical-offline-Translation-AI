export const supportedLanguages = ['en', 'zh', 'ru'] as const;
export type Language = (typeof supportedLanguages)[number];

export function isValidPair(source: Language, target: Language): boolean {
  return source !== target;
}

export function isPairReadyForTurn(options: {
  ready: boolean;
  busy: boolean;
  recording: boolean;
  pairError: string | null;
}): boolean {
  return options.ready && !options.busy && !options.recording && !options.pairError;
}

export function isPairReadyForSpeech(targetVoiceError: string | null): boolean {
  return targetVoiceError === null;
}

export function shouldDiscardStaleTranslation(options: {
  requestTicket: number;
  currentTicket: number;
  requestedText: string;
  currentText: string;
  requestedSource: Language;
  currentSource: Language;
  requestedTarget: Language;
  currentTarget: Language;
}): boolean {
  return (
    options.requestTicket !== options.currentTicket ||
    options.requestedText !== options.currentText ||
    options.requestedSource !== options.currentSource ||
    options.requestedTarget !== options.currentTarget
  );
}

export function inferCancellationStatus(errorMessage: string): string {
  return errorMessage.toLowerCase().includes('cancel')
    ? 'Recording cancelled.'
    : errorMessage;
}
