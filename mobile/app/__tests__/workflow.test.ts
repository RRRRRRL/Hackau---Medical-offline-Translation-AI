import {
  inferCancellationStatus,
  isPairReadyForSpeech,
  isPairReadyForTurn,
  isValidPair,
  shouldDiscardStaleTranslation,
} from '../src/workflow';

describe('mobile workflow helpers', () => {
  it('supports readiness for valid language pairs', () => {
    expect(isValidPair('en', 'zh')).toBe(true);
    expect(isValidPair('en', 'en')).toBe(false);
    expect(isPairReadyForSpeech(null)).toBe(true);
    expect(isPairReadyForSpeech('Install ru voice')).toBe(false);
  });

  it('flags invalid pairs and stale translation results', () => {
    expect(
      shouldDiscardStaleTranslation({
        requestTicket: 2,
        currentTicket: 3,
        requestedText: 'abc',
        currentText: 'abc',
        requestedSource: 'en',
        currentSource: 'en',
        requestedTarget: 'zh',
        currentTarget: 'zh',
      }),
    ).toBe(true);

    expect(
      shouldDiscardStaleTranslation({
        requestTicket: 3,
        currentTicket: 3,
        requestedText: 'abc',
        currentText: 'abc',
        requestedSource: 'en',
        currentSource: 'en',
        requestedTarget: 'zh',
        currentTarget: 'zh',
      }),
    ).toBe(false);
  });

  it('treats cancellation distinctly and blocks turns while busy/error', () => {
    expect(inferCancellationStatus('Recording cancelled because app moved to background')).toBe('Recording cancelled.');
    expect(inferCancellationStatus('No speech recognized')).toBe('No speech recognized');

    expect(
      isPairReadyForTurn({
        ready: true,
        busy: false,
        recording: false,
        pairError: null,
      }),
    ).toBe(true);

    expect(
      isPairReadyForTurn({
        ready: true,
        busy: true,
        recording: false,
        pairError: null,
      }),
    ).toBe(false);
  });
});
