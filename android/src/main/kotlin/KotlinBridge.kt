import okhttp3.*
import java.io.IOException
import kotlin.coroutines.*


class KotlinBridge {
    suspend fun executeAsync(call: Call): Response {
        return suspendCoroutine { continuation ->

            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    continuation.resume(response)
                }

                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(e)
                }
            })
        }
    }
}


