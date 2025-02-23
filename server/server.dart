import 'dart:io';
import 'dart:convert';
import 'dart:math';

final Map<String, WebSocket> clients = {};
final String address = '0.0.0.0';
final int port = 8080;

void main() async {
  //listens for HTTP requests on that specific address at that port.
  HttpServer server = await HttpServer.bind(address, port);
  print('Websocket Listening on $address:${port}');

  await for (HttpRequest request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocket socket = await WebSocketTransformer.upgrade(request);
      print('upgraded');
      handleConnection(socket);
    } else {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    }
  }
}

void handleConnection(WebSocket socket) {
  String clientId = generateClientId();
  clients[clientId] = socket;
  print('Client connected: $clientId');

  socket.add(jsonEncode({'type': 'welcome', 'id': clientId}));
  if (clientId == 'clientB') {
    clients['clientA']!.add(jsonEncode({'type': 'connected'}));
  }

  socket.listen(
    (message) {
      print('Received message: $message');
      var data = jsonDecode(message);
      switch (data['type']) {
        case 'signal':
          forward(data, clientId, 'signal');
          break;
        case 'offer':
          forward(data, clientId, 'offer');
          break;
        case 'answer':
          forward(data, clientId, 'answer');
          break;
        default:
          print('Unknown message type: ${data['type']}');
      }
    },
    onDone: () {
      clients.remove(clientId);
      print('Client disconnected: $clientId');
    },
  );
}

void forward(data, clientId, String type) {
  String targetId = data['target'];
  if (clients.containsKey(targetId)) {
    clients[targetId]!.add(
      jsonEncode({'type': type, 'from': clientId, 'data': data['data']}),
    );
  }
}

String generateClientId() {
  if (clients.isEmpty) {
    return 'clientA';
  }
  if (clients.length == 1) {
    return 'clientB';
  }
  if (clients.length == 2) {
    return 'clientC';
  } else {
    return 'No Client Id';
  }
}
