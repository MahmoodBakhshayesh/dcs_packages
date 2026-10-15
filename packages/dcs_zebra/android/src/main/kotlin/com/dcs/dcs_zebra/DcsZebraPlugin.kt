package com.dcs.dcs_zebra

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class DcsZebraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
  EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
  private lateinit var channel: MethodChannel
  private lateinit var discoverEvents: EventChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private val executor = Executors.newCachedThreadPool()
  private val mainHandler = Handler(Looper.getMainLooper())
  private val connections = ConcurrentHashMap<String, Connection>()
  private val printers = ConcurrentHashMap<String, ZebraPrinter>()

  private var discoverSink: EventChannel.EventSink? = null
  private val discoverCancelled = AtomicBoolean(false)
  private var permissionResult: Result? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "dcs_zebra")
    channel.setMethodCallHandler(this)
    discoverEvents = EventChannel(binding.binaryMessenger, "dcs_zebra/discover")
    discoverEvents.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    discoverEvents.setStreamHandler(null)
    connections.values.forEach { runCatching { it.close() } }
    connections.clear()
    printers.clear()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    discoverSink = events
  }

  override fun onCancel(arguments: Any?) {
    discoverCancelled.set(true)
    discoverSink = null
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
          val found = discover(types, timeoutMs, stream = false)
          mainHandler.post { result.success(found) }
        } catch (e: Exception) {
          mainHandler.post { result.error("discover_failed", e.message, null) }
        }
      }
      "startDiscover" -> {
        discoverCancelled.set(false)
        val types = call.argument<List<String>>("types") ?: emptyList()
        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: 8000L)
        // Return immediately; discovery emits on the EventChannel.
        result.success(null)
        executor.execute {
          try {
            discover(types, timeoutMs, stream = true)
            mainHandler.post {
              discoverSink?.success(mapOf("done" to true))
            }
          } catch (e: Exception) {
            mainHandler.post {
              discoverSink?.error("discover_failed", e.message, null)
            }
          }
        }
      }
      "cancelDiscover" -> {
        discoverCancelled.set(true)
        result.success(null)
      }
      "pair" -> executor.execute {
        try {
          val address = call.argument<String>("address")
            ?: throw IllegalArgumentException("address required")
          val outcome = pairDevice(address)
          mainHandler.post { result.success(outcome) }
        } catch (e: Exception) {
          mainHandler.post { result.error("pair_failed", e.message, null) }
        }
      }
      "unpair" -> executor.execute {
        try {
          val address = call.argument<String>("address")
            ?: throw IllegalArgumentException("address required")
          val outcome = unpairDevice(address)
          mainHandler.post { result.success(outcome) }
        } catch (e: Exception) {
          mainHandler.post { result.error("unpair_failed", e.message, null) }
        }
      }
      "bondedPrinters" -> executor.execute {
        try {
          mainHandler.post { result.success(bondedPrinters()) }
        } catch (e: Exception) {
          mainHandler.post { result.error("bonded_failed", e.message, null) }
        }
      }
      "pairedAccessories" -> executor.execute {
        // Android uses bonded devices; keep API parity with iOS.
        try {
          mainHandler.post { result.success(bondedPrinters()) }
        } catch (e: Exception) {
          mainHandler.post { result.error("paired_failed", e.message, null) }
        }
      }
      "ensureBluetoothPermissions" -> ensureBluetoothPermissions(result)
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

  private fun ensureBluetoothPermissions(result: Result) {
    val act = activity
    if (act == null) {
      result.success("denied")
      return
    }
    val needed = requiredBluetoothPermissions().filter {
      ContextCompat.checkSelfPermission(act, it) != PackageManager.PERMISSION_GRANTED
    }
    if (needed.isEmpty()) {
      result.success("granted")
      return
    }
    permissionResult = result
    ActivityCompat.requestPermissions(act, needed.toTypedArray(), PERMISSION_REQUEST)
  }

  private fun requiredBluetoothPermissions(): List<String> {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      listOf(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
      )
    } else {
      listOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    if (requestCode != PERMISSION_REQUEST) return false
    val pending = permissionResult ?: return false
    permissionResult = null
    val act = activity
    if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
      pending.success("granted")
      return true
    }
    val permanentlyDenied = act != null && permissions.any {
      !ActivityCompat.shouldShowRequestPermissionRationale(act, it) &&
        ContextCompat.checkSelfPermission(act, it) != PackageManager.PERMISSION_GRANTED
    }
    pending.success(if (permanentlyDenied) "permanentlyDenied" else "denied")
    return true
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

  private fun bondedAddresses(): Set<String> {
    return runCatching {
      @Suppress("DEPRECATION")
      val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptySet()
      adapter.bondedDevices?.mapNotNull { it.address?.uppercase() }?.toSet() ?: emptySet()
    }.getOrDefault(emptySet())
  }

  private fun isPaired(address: String): Boolean {
    val normalized = address.uppercase()
    return bondedAddresses().any { it == normalized || normalized.contains(it) }
  }

  private fun parseRssi(map: Map<String, String>?): Int? {
    if (map == null) return null
    val keys = listOf("RSSI", "rssi", "SIGNAL_STRENGTH", "SIGNAL")
    for (key in keys) {
      val raw = map[key] ?: continue
      raw.toIntOrNull()?.let { return it }
      raw.replace(Regex("[^0-9\\-]"), "").toIntOrNull()?.let { return it }
    }
    return null
  }

  private fun printerMap(
    type: String,
    address: String,
    printer: DiscoveredPrinter,
  ): Map<String, Any?> {
    val data = printer.discoveryDataMap
    val name = data["PRODUCT_NAME"]
      ?: data["FRIENDLY_NAME"]
      ?: address
    val model = data["MODEL_NAME"]
    return mapOf(
      "id" to "$type:$address",
      "address" to address,
      "connectionType" to type,
      "name" to name,
      "macAddress" to (data["MAC_ADDRESS"] ?: if (address.contains(":")) address else null),
      "serialNumber" to data["SERIAL_NUMBER"],
      "model" to model,
      "manufacturer" to (data["COMPANY_NAME"] ?: data["MANUFACTURER"] ?: "Zebra"),
      "rssi" to parseRssi(data),
      "paired" to isPaired(data["MAC_ADDRESS"] ?: address),
    )
  }

  private fun discover(
    types: List<String>,
    timeoutMs: Long,
    stream: Boolean,
  ): List<Map<String, Any?>> {
    val found = LinkedHashMap<String, Map<String, Any?>>()
    val wanted = if (types.isEmpty()) {
      listOf("tcp", "bluetooth", "bluetoothLe", "usb")
    } else {
      types
    }
    val remaining = java.util.concurrent.atomic.AtomicInteger(0)
    val latch = CountDownLatch(1)
    val finished = AtomicBoolean(false)

    fun finishOnce() {
      if (finished.compareAndSet(false, true)) {
        latch.countDown()
      }
    }

    fun emit(map: Map<String, Any?>) {
      val id = map["id"] as? String ?: return
      if (found.put(id, map) != null) return
      if (stream) {
        mainHandler.post { discoverSink?.success(map) }
      }
    }

    val handler = object : DiscoveryHandler {
      override fun foundPrinter(printer: DiscoveredPrinter) {
        if (discoverCancelled.get()) return
        val address = printer.address ?: return
        val type = when {
          wanted.contains("usb") && printer.toString().contains("Usb", ignoreCase = true) -> "usb"
          wanted.contains("bluetoothLe") && !address.contains(".") -> {
            // Prefer BLE when both BT types requested and address looks like MAC.
            if (wanted.contains("bluetooth") && isPaired(address)) "bluetooth" else
              if (wanted.contains("bluetoothLe")) "bluetoothLe" else "bluetooth"
          }
          wanted.contains("bluetooth") && address.contains(":") -> "bluetooth"
          address.contains(".") -> "tcp"
          else -> if (wanted.contains("bluetoothLe")) "bluetoothLe" else "bluetooth"
        }
        if (!wanted.contains(type)) return
        emit(printerMap(type, address, printer))
      }

      override fun discoveryFinished() {
        if (remaining.decrementAndGet() <= 0) finishOnce()
      }

      override fun discoveryError(message: String?) {
        if (remaining.decrementAndGet() <= 0) finishOnce()
      }
    }

    val starters = mutableListOf<() -> Unit>()
    if (wanted.contains("tcp")) starters += { NetworkDiscoverer.findPrinters(handler) }
    if (wanted.contains("bluetooth")) starters += {
      BluetoothDiscoverer.findPrinters(context, handler)
    }
    if (wanted.contains("bluetoothLe")) starters += {
      BluetoothLeDiscoverer.findPrinters(context, handler)
    }
    if (wanted.contains("usb")) starters += { UsbDiscoverer.findPrinters(context, handler) }

    remaining.set(starters.size.coerceAtLeast(1))
    if (starters.isEmpty()) {
      finishOnce()
    } else {
      starters.forEach { runCatching { it() } }
    }

    latch.await(timeoutMs, TimeUnit.MILLISECONDS)
    return found.values.toList()
  }

  private fun bondedPrinters(): List<Map<String, Any?>> {
    @Suppress("DEPRECATION")
    val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
    return adapter.bondedDevices?.map { device ->
      val address = device.address ?: ""
      mapOf(
        "id" to "bluetooth:$address",
        "address" to address,
        "connectionType" to "bluetooth",
        "name" to (device.name ?: address),
        "macAddress" to address,
        "model" to null,
        "manufacturer" to "Zebra",
        "rssi" to null,
        "paired" to true,
      )
    } ?: emptyList()
  }

  private fun pairDevice(address: String): String {
    @Suppress("DEPRECATION")
    val adapter = BluetoothAdapter.getDefaultAdapter()
      ?: return "failed"
    val device = adapter.getRemoteDevice(address)
    if (device.bondState == BluetoothDevice.BOND_BONDED) return "alreadyPaired"

    val latch = CountDownLatch(1)
    val outcome = arrayOf("failed")
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(ctx: Context?, intent: Intent?) {
        if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
        val bondedDevice =
          intent.getParcelableExtraCompat<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
        if (bondedDevice?.address?.equals(address, ignoreCase = true) != true) return
        when (intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)) {
          BluetoothDevice.BOND_BONDED -> {
            outcome[0] = "paired"
            latch.countDown()
          }
          BluetoothDevice.BOND_NONE -> {
            outcome[0] = "failed"
            latch.countDown()
          }
        }
      }
    }
    context.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
    return try {
      val started = device.createBond()
      if (!started) return "failed"
      latch.await(30, TimeUnit.SECONDS)
      outcome[0]
    } finally {
      runCatching { context.unregisterReceiver(receiver) }
    }
  }

  private fun unpairDevice(address: String): String {
    @Suppress("DEPRECATION")
    val adapter = BluetoothAdapter.getDefaultAdapter() ?: return "failed"
    val device = adapter.getRemoteDevice(address)
    if (device.bondState == BluetoothDevice.BOND_NONE) return "unpaired"
    return try {
      val method = device.javaClass.getMethod("removeBond")
      val ok = method.invoke(device) as Boolean
      if (ok) "unpaired" else "failed"
    } catch (_: Exception) {
      "failed"
    }
  }

  private inline fun <reified T> Intent.getParcelableExtraCompat(key: String): T? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      getParcelableExtra(key, T::class.java)
    } else {
      @Suppress("DEPRECATION")
      getParcelableExtra(key) as? T
    }
  }

  companion object {
    private const val PERMISSION_REQUEST = 0xDC5B
  }
}
