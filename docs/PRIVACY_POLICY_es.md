# Política de Privacidad de KintaMed Edge 🛡️

**Última actualización: 23 de enero de 2026**

KintaMed Edge se compromete a proteger la privacidad y seguridad de los datos de los pacientes manejados por los Agentes de Salud Comunitarios (ASC). Esta Política de Privacidad explica nuestra filosofía de datos "Cero-Nube" (Zero-Cloud) y cómo garantizamos la confidencialidad absoluta en el campo.

---

## 1. Filosofía de datos Cero-Nube
KintaMed Edge es una aplicación **primero fuera de línea (offline-first)**. **No recopilamos, transmitimos ni almacenamos ningún dato en servidores externos, proveedores de la nube o bases de datos de terceros.**

Todo lo que ingresa en la aplicación permanece en el dispositivo físico donde está instalada la aplicación.

## 2. Datos que procesamos localmente
Para proporcionar apoyo en la toma de decisiones clínicas, la aplicación procesa los siguientes datos exclusivamente en su dispositivo:
- **Demografía del paciente**: Nombre, edad, género, fecha de nacimiento.
- **Datos clínicos**: Signos vitales (PA, SpO2, frecuencia cardíaca, etc.), síntomas e historial médico.
- **Medios clínicos**: Fotos de heridas, erupciones o imágenes de diagnóstico.
- **Grabaciones de voz**: Procesamiento de audio temporal para la conversión de voz a texto.

## 3. Seguridad y cifrado de datos
Todos los datos almacenados en el dispositivo están protegidos por **SQLCipher**, que proporciona un cifrado de grado militar (AES-256). Esto garantiza que incluso si el dispositivo físico se pierde o es robado, la información del paciente no pueda ser accedida sin las credenciales autorizadas de la aplicación.

## 4. Permisos requeridos
La aplicación solicita permisos específicos para funcionar en el campo:
- **Cámara**: Para capturar imágenes clínicas para el análisis de IA.
- **Micrófono**: Para permitir la grabación de síntomas con manos libres.
- **Almacenamiento/Sistema de archivos**: Para almacenar los pesos del modelo de IA MedGemma (~3 GB) y la base de datos local cifrada.

## 5. Acceso de terceros
No hay **ningún acceso de terceros** a sus datos. Debido a que la aplicación no se conecta a Internet para sus funciones principales, no se pueden compartir datos con anunciantes, proveedores de análisis o agencias gubernamentales.

## 6. Retención de datos
Los datos se retienen en su dispositivo hasta que elimine manualmente una evaluación o borre los datos de la aplicación. Los usuarios son responsables de realizar purgas de datos periódicas de acuerdo con los protocolos de su organización de salud local.

## 7. Contacto
Para preguntas sobre la implementación técnica de esta política de privacidad, comuníquese con el equipo de desarrollo en nuestro repositorio.

---
**Nota**: Al usar KintaMed Edge, usted reconoce que es responsable de la seguridad física del dispositivo y de la confidencialidad de cualquier dato del paciente que se muestre en la pantalla.
