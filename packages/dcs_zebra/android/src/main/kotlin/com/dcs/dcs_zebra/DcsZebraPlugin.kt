package com.dcs.dcs_zebra

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.zebra.sdk.btleComm.BluetoothLeConnection
import com.zebra.sdk.btleComm.BluetoothLeDiscoverer
import com.zebra.sdk.comm.BluetoothConnection
import com.zebra.sdk.comm.Connection
import com.zebra.sdk.comm.ConnectionException
import com.zebra.sdk.comm.TcpConnection
import com.zebra.sdk.printer.PrinterStatus
import com.zebra.sdk.printer.ZebraPrinter
import com.zebra.sdk.printer.ZebraPrinterFactory
import com.zebra.sdk.printer.discovery.DiscoveredPrinter
import com.zebra.sdk.printer.discovery.DiscoveryHandler
import com.zebra.sdk.printer.discovery.NetworkDiscoverer
import com.zebra.sdk.printer.discovery.BluetoothDiscoverer
import com.zebra.sdk.printer.discovery.UsbDiscoverer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class DcsZebraPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private val executor = Executors.newCachedThreadPool()
  private val mainHandler = Handler(Looper.getMainLooper())
  private val connections = ConcurrentHashMap<String, Connection>()
  private val printers = ConcurrentHashMap<String, ZebraPrinter>()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "dcs_zebra")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    connections.values.forEach { runCatching { it.close() } }
    connections.clear()
    printers.clear()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "capabilities" -> result.success(
        mapOf(
          "tcp" to true,
          "bluetooth" to true,
          "bluetoothLe" to true,
          "usb" to true,
        ),
      )
      "discover" -> executor.execute {
        try {
          val types = call.argument<List<String>>("types") ?: emptyList()
          val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 8000L)
          val found = discover(types, timeoutMs)
          mainHandler.post { result.success(found) }
        } catch (e: Exception) {
          mainHandler.post { result.error("discover_failed", e.message, null) }
        }
      }
      "connect" -> executor.execute {
        try {
          val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
          val address = call.argument<String>("address") ?: throw IllegalArgumentException("address required")
          val type = call.argument<String>("connectionType") ?: "tcp"
          val timeoutMs = call.argument<Number>("timeoutMs")?.toInt() ?: 10000
          connect(id, address, type, timeoutMs)
          mainHandler.post { result.success(null) }
        } catch (e: Exception) {
          mainHandler.post { result.error("connect_failed", e.message, null) }
        }
      }
      "disconnect" -> executor.execute {
        try {
          val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
          disconnect(id)
          mainHandler.post { result.success(null) }
        } catch (e: Exception) {
          mainHandler.post { result.error("disconnect_failed", e.message, null) }
        }
      }
      "write" -> executor.execute {
        try {
          val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
          val bytes = call.argument<ByteArray>("bytes")
            ?: throw IllegalArgumentException("bytes required")
          val connection = connections[id] ?: throw IllegalStateException("Not connected")
          connection.write(bytes)
          mainHandler.post { result.success(null) }
        } catch (e: Exception) {
          mainHandler.post { result.error("write_failed", e.message, null) }
        }
      }
      "read" -> executor.execute {
        try {
          val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
          val timeoutMs = call.argument<Number>("timeoutMs")?.toInt() ?: 2000
          val connection = connections[id] ?: throw IllegalStateException("Not connected")
          connection.setMaxTimeoutForRead(timeoutMs)
          connection.setTimeToWaitForMoreData(timeoutMs)
          val data = connection.read()
          mainHandler.post { result.success(data) }
        } catch (e: Exception) {
          mainHandler.post { result.success(null) }
        }
      }
      "getStatus" -> executor.execute {
        try {
          val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
          val printer = printers[id]
          if (printer == null) {
            mainHandler.post { result.success(null) }
            return@execute
          }
          val status: PrinterStatus = printer.currentStatus
          mainHandler.post {
            result.success(
              mapOf(
                "isReadyToPrint" to status.isReadyToPrint,
                "isPaperOut" to status.isPaperOut,
                "isHeadOpen" to status.isHeadOpen,
                "isRibbonOut" to status.isRibbonOut,
                "isPaused" to status.isPaused,
                "isReceiveBufferFull" to status.isReceiveBufferFull,
              ),
            )
          }
        } catch (e: Exception) {
          mainHandler.post { result.error("status_failed", e.message, null) }
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun connect(id: String, address: String, type: String, timeoutMs: Int) {
    disconnect(id)
    val connection: Connection = when (type) {
      "bluetooth" -> BluetoothConnection(address)
      "bluetoothLe" -> BluetoothLeConnection(address, context)
      "usb" -> throw ConnectionException(
        "USB connections require a UsbDevice from discovery; use discover+connect with usb address.",
      )
      else -> {
        val parts = address.split(":")
        val host = parts[0]
        val port = if (parts.size > 1) parts[1].toIntOrNull() ?: TcpConnection.DEFAULT_ZPL_TCP_PORT
        else TcpConnection.DEFAULT_ZPL_TCP_PORT
        TcpConnection(host, port)
      }
    }
    connection.setMaxTimeoutForRead(timeoutMs)
    connection.setTimeToWaitForMoreData(timeoutMs)
    connection.open()
    connections[id] = connection
    try {
      printers[id] = ZebraPrinterFactory.getInstance(connection)
    } catch (_: Exception) {
      // Language detection may fail on some units; write still works.
    }
  }

  private fun disconnect(id: String) {
    printers.remove(id)
    val connection = connections.remove(id) ?: return
    runCatching { connection.close() }
  }

  private fun discover(types: List<String>, timeoutMs: Long): List<Map<String, Any?>> {
    val found = LinkedHashMap<String, Map<String, Any?>>()
    val wanted = if (types.isEmpty()) {
      listOf("tcp", "bluetooth", "bluetoothLe", "usb")
    } else {
      types
    }
    val latch = CountDownLatch(1)
    val handler = object : DiscoveryHandler {
      override fun foundPrinter(printer: DiscoveredPrinter) {
        val address = printer.address ?: return
        val type = when {
          wanted.contains("usb") && printer.toString().contains("Usb", ignoreCase = true) -> "usb"
          wanted.contains("bluetoothLe") -> "bluetoothLe"
          wanted.contains("bluetooth") && address.contains(":") -> "bluetooth"
          else -> "tcp"
        }
        if (!wanted.contains(type) && type != "tcp") return
        if (type == "tcp" && !wanted.contains("tcp")) return
        val id = "$type:$address"
        found[id] = mapOf(
          "id" to id,
          "address" to address,
          "connectionType" to type,
          "name" to (printer.discoveryDataMap["PRODUCT_NAME"]
            ?: printer.discoveryDataMap["FRIENDLY_NAME"]
            ?: address),
          "macAddress" to printer.discoveryDataMap["MAC_ADDRESS"],
          "serialNumber" to printer.discoveryDataMap["SERIAL_NUMBER"],
          "model" to printer.discoveryDataMap["MODEL_NAME"],
        )
      }

      override fun discoveryFinished() {
        latch.countDown()
      }

      override fun discoveryError(message: String?) {
        latch.countDown()
      }
    }

    runCatching {
      if (wanted.contains("tcp")) NetworkDiscoverer.findPrinters(handler)
      if (wanted.contains("bluetooth")) BluetoothDiscoverer.findPrinters(context, handler)
      if (wanted.contains("bluetoothLe")) BluetoothLeDiscoverer.findPrinters(context, handler)
      if (wanted.contains("usb")) UsbDiscoverer.findPrinters(context, handler)
    }

    latch.await(timeoutMs, TimeUnit.MILLISECONDS)
    return found.values.toList()
  }
}
