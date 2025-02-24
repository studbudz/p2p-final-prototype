import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart'; // Flutter import for UI components

/*
1. Connect to the server
2. Receive the client ID from the server
3. Create a peer connection
4. define onDataChannel callback
  created so that it is already there when the client gets signals
5. Create a data channel
6. receive an Offer from client A
7. setRemoteDescription
8. exchange ICE candidates with client A
9. accept ICE candidate
10. Communicate with client A
*/

/*
Definitions and clarifications:

Server forwards data based on the signal type. This is defined by You e.g 'welcome'
.listen continuously checks for messages

- callback -> a function that is called when a certain event occurs
- remote description -> a description of the remote peer connection (don't know why we need it)
- ICE -> Interactive Connectivity Establishment is a protocol that helps peers determine the best network path for communication.
- ICE candidate -> a possible network path for communication
*/

//ONLY NEED TO IMPLEMENT THE FOLLOWING:
//ICE CANDIDATE HANDLING

class ClientB {
  String clientId = '';
  late WebSocketChannel _channel;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  ClientB() {
    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));
    print('Client B connected to server');

    _channel.stream.listen(
      (message) => _handleSignal(message),
      onDone: () => print('Connection closed.'),
      onError: (error) => print('Error: $error'), // Uncomment to handle errors
    );
  }

  void _handleSignal(message) {
    try {
      var data = jsonDecode(message);
      print('Client B Received signal: $data');
      switch (data['type']) {
        case 'welcome':
          clientId = data['id'];
          print('Client B Received client ID: $clientId');
          _createPeerConnection();
          break;
        case 'offer':
          _handleOffer(data);
          break;
        case 'ice_candidate':
          print('Client B Received ICE candidate');
          _handleIceCandidate(data['data']['candidate']);
          break;
        default:
          print('Unknown message type: ${data['type']}');
      }
    } catch (error) {
      print('Error: $error'); // Uncomment to see the error
    }
  }

  Future<void> _createPeerConnection() async {
    print('Creating client B peer connection');
    try {
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        print('Client B: ICE candidate: ${candidate.toMap()}');
        _sendSignal({'candidate': candidate.toMap()}, 'ice_candidate');
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('Client B ICE Connection State: $state');
      };

      print('Peer connection created successfully');
    } catch (e, stack) {
      print('Error creating peer connection: $e');
      print(stack);
    }

    _peerConnection!.onDataChannel = _onDataChannel;
  }

  void _handleOffer(data) async {
    print('Client B Received offer');
    // print(data['data']);
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['data']['sdp'], data['data']['type']),
    );

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _sendSignal(answer.toMap(), 'answer');
  }

  //definitions for callbacks
  void _handleIceCandidate(Map<String, dynamic> candidateData) {
    print("Client B: Received ICE Candidate");
    RTCIceCandidate candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    _peerConnection!.addCandidate(candidate);
  }

  void _onDataChannel(RTCDataChannel channel) {
    print('Client B Received data channel');
    _dataChannel = channel;
    print('Data channel ready');
    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      print('Data channel state: $state');
      sendMessage('Hello from client B');
    };
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      print('Client B Received message: ${message.text}');
      sendMessage('Hello from client B');
    };
  }

  void _sendSignal(dynamic data, String type) {
    print('sending signal');
    _channel.sink.add(
      jsonEncode({
        'type': type,
        'target': 'clientA',
        'from': 'clientB',
        'data': data,
      }),
    );
  }

  void sendMessage(String message) {
    if (_dataChannel != null) {
      _dataChannel!.send(RTCDataChannelMessage(message));
      print('Client B sent message: $message');
    } else {
      print('Data channel not established yet');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter bindings are initialized
  await Future.delayed(Duration(seconds: 1));
  ClientB clientB = ClientB();
  // Keep program alive
  await Future.delayed(Duration(days: 1));
  while (true) {
    await Future.delayed(Duration(seconds: 1));
    clientB.sendMessage('Hello from client B');
  }
}
