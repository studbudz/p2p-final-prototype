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
6. send an Offer to client B
7. setRemoteDescription
8. exchange ICE candidates with client B
9. accept ICE candidate
10. Communicate with client B
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

class ClientA {
  String clientId = '';
  late WebSocketChannel _channel;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool connected = false;

  ClientA() {
    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));
    print('Client A connected to server');

    _channel.stream.listen(
      (message) => _handleSignal(message),
      onDone: () => print('Connection closed.'),
      onError: (error) => print('Error: $error'),
    );
  }

  void _handleSignal(message) {
    try {
      var data = jsonDecode(message);
      print('Client A Received signal: $data');
      switch (data['type']) {
        //1. Receive the client ID from the server
        case 'welcome':
          clientId = data['id'];
          print('Client A Received client ID: $clientId');
          break;
        //2. client B is connected
        case 'connected':
          connected = true;
          print('Client A Received connected signal from B');
          _createPeerConnection();
          break;
        //4. Receive an answer from client B
        case 'answer':
          _handleAnswer(data);
          break;
        case 'ice_candidate':
          print('Client A Received ICE candidate');
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
    print('Creating client A peer connection');
    try {
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        print('Client A: ICE candidate: ${candidate.toMap()}');
        _sendSignal({'candidate': candidate.toMap()}, 'ice_candidate');
      };
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('Client A ICE Connection State: $state');
      };

      print('Peer connection created successfully');
    } catch (e, stack) {
      print('Error creating peer connection: $e'); // Uncomment to see the error
      print(stack); // Uncomment to see stack trace
    }

    _peerConnection!.onDataChannel = (channel) {
      print('Client A Received data channel');
      _dataChannel = channel;
      print('Data channel ready');
      _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
        print('Data channel state: $state');
      };
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        print('Client A Received message: ${message.text}');
      };
    };

    print('Creating data channel.');
    _dataChannel = await _peerConnection!.createDataChannel(
      "chat",
      RTCDataChannelInit(),
    );

    _dataChannel!.onMessage = (msg) {
      print("DEBUG: Data channel message received: ${msg.text}");
      sendMessage('Hello from client A');
    };

    _dataChannel!.onDataChannelState = (state) {
      print("DEBUG: Data channel state changed: $state");

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print("DEBUG: Data channel is open.");
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        print("DEBUG: Data channel is closed.");
      }
    };

    print("DEBUG: Data channel created (Client A).");

    //3. Create an offer to send to client B
    RTCSessionDescription offer = await _peerConnection!.createOffer();

    await _peerConnection!.setLocalDescription(offer);

    _sendSignal(offer.toMap(), 'offer');
  }

  void _handleAnswer(data) async {
    print('Client A Received answer');
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['data']['sdp'], 'answer'),
    );
  }

  void _handleIceCandidate(Map<String, dynamic> candidateData) {
    print("Client A: Received ICE Candidate");
    RTCIceCandidate candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    _peerConnection!.addCandidate(candidate);
  }

  void _sendSignal(dynamic data, String type) {
    print('sending signal');
    _channel.sink.add(
      jsonEncode({
        'type': type,
        'target': 'clientB',
        'from': 'clientA',
        'data': data,
      }),
    );
  }

  void sendMessage(String message) {
    if (_dataChannel != null) {
      _dataChannel!.send(RTCDataChannelMessage(message));
      print('Client A sent message: $message');
    } else {
      print('Data channel not established yet');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter bindings are initialized
  await Future.delayed(Duration(seconds: 1));
  ClientA clientA = ClientA();
  // Keep program alive
  await Future.delayed(Duration(days: 1));
  while (true) {
    await Future.delayed(Duration(seconds: 1));
    clientA.sendMessage('Hello from client A');
  }
}
