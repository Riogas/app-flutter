import 'dart:convert';
import 'package:jose/jose.dart';
import 'package:http/http.dart' as http;

void main() async {
  const serviceAccountJson = '''
{
  "type": "service_account",
  "project_id": "riogas-pedidos",
  "private_key_id": "c02e618a57da3f7780e9f1980ffeb18c32dbe143",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDEkQjr9oYmjakg\\npXArLakPQaSWTqIIqRoT5aud5DHK+bGccT3qO2GV3Y4gG1S4yUP7rGvjcwj1WlSE\\nRdCcCpqrd/QfzqlwBB6lFkI0Ucat3c3/LshLm2NcOVqtK1GlEhYkcrKUGmtCeHX+\\nLS/ZdoqoXwjSZ1JdqsjkU7PTCEgUGXMWS1+fnJO9wXQ41ex9Or7B5xDbEY+ZUqig\\nu+4sSP5TPwq+Xoy8OH5P8kRCGqKW0wH7P+0vKnFiZv51fy4Ae87fQBIZZPyS3QQ2\\nMnbqQdVI38My8Yevy2w74b8/gEnOK/FT9q88EEaRIXZ2s7zftDPvQ2tdsdhcoN6c\\nll7wdu3DAgMBAAECggEAL2/w/0EXTuaRElfaohD647urxLplUEG/EV4z9H7FpX5s\\n5pxNnOGHw2sciZMO9ylbRrltsA5q8wtBqkpO9dl5SjhAqgxtx6K24pBkmcvCbuNA\\ne30GyXhOmksdHv19TqD2xwUHI8bca8Y2c4jkK074V3nX3y8gKYq1wKSSmTM+cdrl\\n/Z1IEwj575ahvHazdsyX7Ikv1UlEEYG1rldU7TZRO+/269V+p40RF7f6sXH/YaxT\\nQpJuHA2b/r4UC29+qtTblXEfDs/AKeTpXerCB+rzfO1ApLq+PFPfi9DeVuGVg1hE\\nmwZhkZ6kVD8QccLCGXhpiVpyLnUilKvgzuZcfW7bwQKBgQDt4ZSqi1cNcDmRnMYe\\n+GIrvQ75btImc6jiT1uv0OKic12STL1nifRhVRUDLhiTNBXreNxnnI9Z5B6APU/9\\n17YZrKzgCVTNu8TUWhKnFLDlYANB09QvHrgY7uuBXGqMY+Kf8+zvdFgO9uwAMbbF\\ncOJeBDFkve/VzFLiiCv+4ljRdwKBgQDTid1VH2QA63+TkjamlUpJUkK4ReawUj5P\\n1aH4nksP0/LGmAQqCQc+LmIzVEnIoA507LyZaLh8Klc1rlnBibPdLCdjRQsmRG4+\\nk2oCjPi7d+9SE3Arx0wbwTyE+wqphghx0ti6V3L5RXfQYWyGD7vnPb/fX80hGAi/\\nsV6qlFf5FQKBgQDX7blGKZ+GikUngRhyCmMKct3B2y+VSc2WSBTg/gqLDY91eoU/\\nFAGpzFJ7hX83N8Nh8F6ZCosxPJnXLFCNCh65JX3zC2VYLsZXP7/IvEZqn4G1YjQr\\n5YWU1GMgFKR+9ThEm2WKYqCATPEip/3RMUu5rbKsUKEBACyIhrTw88NNtwKBgDaS\\na2oJVhgyqM/eOYESJH7z3MiDJ/c20GJyH33vADhOGmSHVROvDpJJDwZk6T/7op8h\\nb6o37NgDaEot93PJXYBiYqrmZfDyWGqGRyPvUD+0uiW3ZAm3OXgzirRXuzFupYEP\\nvt+brcqG1FkKuR+AsZ3/PR+YLGgsNh2V2XEyIdvdAoGBAKTUOq1aRfMeHQjZL8mi\\nyqH2G9t8RnZ4pvesyTdy0LK7pa8iLUXIs52fLTD+HTvnKpTOMu/wX2760NGCmUuq\\nrQe4V6rHrPlADmZ0G6nzdU6LQAS9wM3zILoyM8luVbcq2cn00IxRe9cUuaFVBj9+\\nAxROw+UNPk4qQLXb6hgF3RXe\\n-----END PRIVATE KEY-----\\n",
  "client_email": "firebase-adminsdk-fbsvc@riogas-pedidos.iam.gserviceaccount.com",
  "token_uri": "https://oauth2.googleapis.com/token"
}
''';

  // Decodear el JSON
  final serviceAccount = jsonDecode(serviceAccountJson);

  // Arreglar la private key: convertir \\\n en saltos de línea reales
  final cleanPrivateKey =
      (serviceAccount["private_key"] as String).replaceAll(r'\\n', '\\n');
  final privateKey = JsonWebKey.fromPem(cleanPrivateKey);

  // Fechas
  final now = DateTime.now().toUtc();
  final iat = now.millisecondsSinceEpoch ~/ 1000;
  final exp = iat + 3600;

  print('iat: $iat');
  print('exp: $exp');
  print('now: $now');

  // Construir los claims
  final claims = JsonWebTokenClaims.fromJson({
    'iss': serviceAccount["client_email"],
    'scope': 'https://www.googleapis.com/auth/firebase.messaging',
    'aud': serviceAccount["token_uri"],
    'iat': iat,
    'exp': exp,
  });

  // Firmar el JWT
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = claims.toJson()
    ..addRecipient(privateKey, algorithm: 'RS256');

  final jws = builder.build();
  final jwt = jws.toCompactSerialization();

  print('JWT firmado:');
  print(jwt);

  // POST a Google OAuth 2.0 para obtener access token
  final response = await http.post(
    Uri.parse(serviceAccount["token_uri"]),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: {
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': jwt,
    },
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    print('Access Token:');
    print(data['access_token']);
  } else {
    print('Error al obtener el token:');
    print(response.statusCode);
    print(response.body);
  }
}
