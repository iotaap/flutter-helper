import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;

class IoTaaP {
  IoTaaP(this._broker, this._port, this._username, this._passwd,
      this._clientIdentifier);

  Function _payloadCallback; // Callback method

  // Sets the callback method that will be called when message is received
  void setCallback(Function payloadCallback) {
    _payloadCallback = payloadCallback;
  }

  String _broker;
  int _port;
  String _username;
  String _passwd;
  String _clientIdentifier;

  mqtt.MqttClient _client;

  // JSON 'command' preset
  // TODO replace with some data type (Map?)
  var jsonData =
      '{"receiver":"receiver_name","data":{"output":{"pin":2,"type":"digital","value":false}}}';

  StreamSubscription _subscription;

  // Set the device to send data to
  // Can be dynamically updated
  void setReceiver(String name) {
    Map<String, dynamic> parsedJson = json.decode(jsonData);
    parsedJson['device'] = name;
    jsonData = json.encode(parsedJson);
  }

  // Change pin state (binary only!)
  void changeState(int pin, bool state) {
    Map<String, dynamic> parsedJson = json.decode(jsonData);

    parsedJson['data']['output']['pin'] = pin;
    parsedJson['data']['output']['value'] = state;
    jsonData = json.encode(parsedJson);

    this.publishMessage(jsonData, "api/transfer");
  }

  // Connect to the MQTT broker, needs Root certificate
  Future<bool> connect() async {
    _client = mqtt.MqttClient(_broker, _clientIdentifier);
    _client.port = _port;
    _client.secure = true;

    // Load root certificate
    // Must be also added in pubspec.yaml as asset
    ByteData data = await rootBundle.load('lib/iotaap/mqtt/roots.pem');
    final SecurityContext context = SecurityContext.defaultContext;
    context.setTrustedCertificatesBytes(data.buffer.asUint8List());

    _client.securityContext = context;

    _client.setProtocolV311();

    _client.logging(on: false); // Disable console logging

    _client.keepAlivePeriod = 30;

    _client.onDisconnected = _onDisconnected;

    // Await connection and start listening on subscribed topics
    await _client.connect(_username, _passwd);
    if (_client.connectionStatus.state == mqtt.MqttConnectionState.connected) {
      _subscription = _client.updates.listen(_onMessage);
      return true;
    } else {
      _client.disconnect();
      return false;
    }
  }

  // Add topic to the list of subscribed
  void subscribe(String topic) async {
    _client.subscribe(topic, mqtt.MqttQos.atMostOnce);
  }

  // Raw message publish to the topic
  void publishMessage(String message, String topic) {
    final mqtt.MqttClientPayloadBuilder builder =
        mqtt.MqttClientPayloadBuilder();
    builder.addString(message);
    _client.publishMessage(topic, mqtt.MqttQos.atMostOnce, builder.payload);
  }

  // Disconnect from the MQTT broker
  void disconnect() {
    _client.disconnect();
    _onDisconnected();
  }

  // Handle after disconnect
  void _onDisconnected() {
    _client = null;
    _subscription.cancel();
    _subscription = null;
  }

  // Message listener - will handle incoming messages
  void _onMessage(List<mqtt.MqttReceivedMessage> event) {
    final mqtt.MqttPublishMessage recMess =
        event[0].payload as mqtt.MqttPublishMessage;
    final String message =
        mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

/*    print("[MQTT client] message with topic: ${event[0].topic}");
    print("[MQTT client] message with message: ${message}");*/

    // Send message and topic to the callback method
    _payloadCallback(message, event[0].topic);
  }
}
