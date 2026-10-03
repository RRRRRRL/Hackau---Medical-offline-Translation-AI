package com.hacku.fieldtalk.data

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.io.File
import java.io.RandomAccessFile

class PcmAudioRecorder(private val context: Context) {
    private var recorder: AudioRecord? = null
    private var recordingJob: Job? = null
    private var outputFile: File? = null

    @SuppressLint("MissingPermission")
    fun start(scope: CoroutineScope): File {
        check(recorder == null) { "Recording already active" }
        val sampleRate = 16_000
        val minSize = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minSize > 0) { "Audio recording is unavailable" }
        val file = File.createTempFile("fieldtalk-", ".wav", context.cacheDir)
        val audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minSize * 2,
        )
        check(audioRecord.state == AudioRecord.STATE_INITIALIZED) { "Audio recorder initialization failed" }
        recorder = audioRecord
        outputFile = file
        audioRecord.startRecording()
        recordingJob = scope.launch(Dispatchers.IO) { writeWave(audioRecord, file, sampleRate, minSize * 2) }
        return file
    }

    suspend fun stop(): File? {
        recorder?.runCatching { stop() }
        recordingJob?.join()
        recorder?.release()
        recorder = null
        recordingJob = null
        return outputFile.also { outputFile = null }
    }

    private fun writeWave(audioRecord: AudioRecord, file: File, sampleRate: Int, bufferSize: Int) {
        RandomAccessFile(file, "rw").use { wave ->
            writeHeader(wave, sampleRate, 0)
            val buffer = ByteArray(bufferSize)
            var bytesWritten = 0L
            while (audioRecord.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val count = audioRecord.read(buffer, 0, buffer.size)
                if (count > 0) {
                    wave.write(buffer, 0, count)
                    bytesWritten += count
                }
            }
            wave.seek(0)
            writeHeader(wave, sampleRate, bytesWritten)
        }
    }

    private fun writeHeader(file: RandomAccessFile, sampleRate: Int, dataSize: Long) {
        fun littleInt(value: Long) = byteArrayOf(value.toByte(), (value shr 8).toByte(), (value shr 16).toByte(), (value shr 24).toByte())
        fun littleShort(value: Int) = byteArrayOf(value.toByte(), (value shr 8).toByte())
        file.writeBytes("RIFF"); file.write(littleInt(dataSize + 36)); file.writeBytes("WAVEfmt ")
        file.write(littleInt(16)); file.write(littleShort(1)); file.write(littleShort(1))
        file.write(littleInt(sampleRate.toLong())); file.write(littleInt((sampleRate * 2).toLong()))
        file.write(littleShort(2)); file.write(littleShort(16)); file.writeBytes("data"); file.write(littleInt(dataSize))
    }
}
