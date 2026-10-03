declare module 'whisper.rn' {
  export type WhisperContext = {
    transcribe: (
      path: string,
      options: {language: string},
    ) => {
      promise: Promise<{result: string}>;
      stop: () => Promise<void>;
    };
    release: () => Promise<void>;
  };

  export function initWhisper(options: {
    filePath: string;
    useGpu?: boolean;
  }): Promise<WhisperContext>;
}
