import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/providers.dart';

enum AuthView { login, register, verify, recoverEmail, recoverCode }

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  // Common Controllers
  final _usernameController = TextEditingController(); 
  final _emailController = TextEditingController(); 
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController(); // For recovery
  
  // Code Controllers (using a single controller to store the 4-6 digit string)
  final _codeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptTerms = false;
  AuthView _currentView = AuthView.login;
  String _tempUsername = ''; // Used to pass username to verify screen

  // Animation controller for particles
  late AnimationController _particleController;
  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initParticles();
  }

  void _initParticles() {
    _particleController = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 10),
    )..addListener(() {
      setState(() {
        for (var particle in _particles) {
          particle.update();
        }
      });
    })..repeat();

    for (int i = 0; i < 20; i++) {
       _particles.add(_generateParticle());
    }
  }

  Particle _generateParticle() {
    return Particle(
       x: _random.nextDouble(),
       y: _random.nextDouble(),
       speed: _random.nextDouble() * 0.001 + 0.0005,
       radius: _random.nextDouble() * 2 + 1.5,
       opacity: _random.nextDouble() * 0.4 + 0.1,
    );
  }

  @override
  void dispose() {
    _particleController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Main Build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Radial glow background
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF330505), // faint red map center
                  Colors.black,
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          // 1. Particle Background (Shared)
          CustomPaint(
             painter: ParticlePainter(_particles),
             child: Container(),
          ),

          // 2. Content Area
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                constraints: BoxConstraints(maxWidth: 400),
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: _buildCurrentView(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case AuthView.login:
        return _buildLoginView();
      case AuthView.register:
        return _buildRegisterView();
      case AuthView.verify:
        return _buildVerifyView();
      case AuthView.recoverEmail:
        return _buildRecoverEmailView();
      case AuthView.recoverCode:
        return _buildRecoverCodeView();
    }
  }

  // --- Views ---

  Widget _buildLoginView() {
    return Column(
      key: ValueKey('login'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/vnce_4.png', height: 120),
        SizedBox(height: 20),
        Text('Bienvenido', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Ingresa para continuar', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        SizedBox(height: 48),

        _buildTextField(controller: _usernameController, label: 'Usuario'),
        SizedBox(height: 16),
        _buildTextField(controller: _passwordController, label: 'Contraseña', isPassword: true),
        
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _currentView = AuthView.recoverEmail),
            child: Text('¿Olvidaste tu contraseña?', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
        ),
        SizedBox(height: 24),

        _buildActionButton(text: 'Iniciar Sesión', onPressed: _handleLogin),
        SizedBox(height: 24),

        // Register Link (Refined)
        RichText(
          text: TextSpan(
            text: '¿Nuevo en Vanacue? ',
            style: TextStyle(color: Colors.grey[600]),
            children: [
              TextSpan(
                text: 'Regístrate ahora',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                recognizer: TapGestureRecognizer()..onTap = () => setState(() {
                  _currentView = AuthView.register;
                  _usernameController.clear();
                  _emailController.clear();
                  _passwordController.clear();
                  _acceptTerms = false;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterView() {
    return Column(
      key: ValueKey('register'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/vnce_4.png', height: 100),
        SizedBox(height: 20),
        Text('Únete a\nVanacue', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Disfruta de contenido ilimitado', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        SizedBox(height: 40),

        _buildTextField(controller: _usernameController, label: 'Usuario (min 4 letras)'),
        SizedBox(height: 16),
        _buildTextField(controller: _emailController, label: 'Correo electrónico'), 
        SizedBox(height: 16),
        _buildTextField(controller: _passwordController, label: 'Contraseña (min 8 caracteres)', isPassword: true),
        SizedBox(height: 16),

        // Terms Checkbox
        Row(
          children: [
            Theme(
              data: ThemeData(unselectedWidgetColor: Colors.grey),
              child: Checkbox(
                value: _acceptTerms,
                activeColor: Color(0xFFD30000),
                onChanged: (val) => setState(() => _acceptTerms = val ?? false),
              ),
            ),
            Expanded(
              child: RichText(
                text: TextSpan(
                  text: 'He leído y acepto los ',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'Términos y\nCondiciones',
                      style: TextStyle(color: Color(0xFFD30000), fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Color(0xFFD30000)),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final uri = Uri.parse('https://vnc-e.com/terminos.html');
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 24),

        _buildActionButton(text: 'Registrarse', onPressed: () async {
             if (!_acceptTerms) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Debes aceptar los términos y condiciones', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
               return;
             }
             if (_usernameController.text.length < 4) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('El usuario debe tener mínimo 4 letras', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
               return;
             }
             if (_passwordController.text.length < 8) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('La contraseña debe tener mínimo 8 caracteres', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
               return;
             }

             setState(() => _isLoading = true);
             final authProvider = Provider.of<AuthProvider>(context, listen: false);
             final result = await authProvider.api.register(
               _usernameController.text.trim(),
               _emailController.text.trim(),
               _passwordController.text.trim()
             );
             setState(() => _isLoading = false);

             if (result['success'] == true) {
               setState(() {
                 _tempUsername = _usernameController.text.trim();
                 _currentView = AuthView.verify;
                 _codeController.clear();
               });
             } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Error de conexión', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
             }
        }),
        SizedBox(height: 24),

        RichText(
          text: TextSpan(
            text: '¿Ya tienes cuenta? ',
            style: TextStyle(color: Colors.grey[600]),
            children: [
              TextSpan(
                text: 'Inicia sesión',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                recognizer: TapGestureRecognizer()..onTap = () => setState(() => _currentView = AuthView.login),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyView() {
    return Column(
      key: ValueKey('verify'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/vnce_4.png', height: 100),
        SizedBox(height: 20),
        Text('Verificación', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Código enviado a ${_emailController.text}', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        SizedBox(height: 40),

        _buildTextField(controller: _codeController, label: 'Código (4 dígitos)'),
        SizedBox(height: 24),

        _buildActionButton(text: 'Verificar Código', onPressed: () async {
            if (_codeController.text.length < 4) return;
            setState(() => _isLoading = true);
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            final result = await authProvider.api.verifyCode(_tempUsername, _codeController.text.trim());
            setState(() => _isLoading = false);

            if (result['success'] == true) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('¡Cuenta verificada! Ingresa tus datos.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
               setState(() {
                 _currentView = AuthView.login;
                 _passwordController.clear(); // Force re-entry
               });
            } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Error de conexión', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
            }
        }),
      ],
    );
  }

  Widget _buildRecoverEmailView() {
    return Column(
      key: ValueKey('recoverEmail'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/vnce_4.png', height: 100),
        SizedBox(height: 20),
        Text('Recuperar\nCuenta', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Ingresa tu correo para buscarte', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        SizedBox(height: 40),

        _buildTextField(controller: _emailController, label: 'Tu correo registrado'), 
        SizedBox(height: 24),

        _buildActionButton(text: 'Enviar Código de Recuperación', onPressed: () async {
             if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Escribe un correo válido', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
               return;
             }
             
             setState(() => _isLoading = true);
             final authProvider = Provider.of<AuthProvider>(context, listen: false);
             final result = await authProvider.api.forgotPassword(_emailController.text.trim());
             setState(() => _isLoading = false);

             if (result['success'] == true) {
                 setState(() {
                   _currentView = AuthView.recoverCode;
                   _codeController.clear();
                   _newPasswordController.clear();
                 });
             } else {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Error de conexión', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
             }
        }),
        SizedBox(height: 24),

        TextButton(
          onPressed: () => setState(() => _currentView = AuthView.login),
          child: Text('Volver al Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildRecoverCodeView() {
    return Column(
      key: ValueKey('recoverCode'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/vnce_4.png', height: 100),
        SizedBox(height: 20),
        Text('Recuperar\nCuenta', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('Código enviado. Revisa tu correo.', style: TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
        SizedBox(height: 40),

        _buildTextField(controller: _codeController, label: 'Código (6 dígitos)'),
        SizedBox(height: 16),
        _buildTextField(controller: _newPasswordController, label: 'Nueva Contraseña', isPassword: true),
        SizedBox(height: 24),

        _buildActionButton(text: 'Guardar Nueva Contraseña', onPressed: () async {
            if (_codeController.text.isEmpty || _newPasswordController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Llena todos los campos', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
              return;
            }

            setState(() => _isLoading = true);
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            final result = await authProvider.api.resetPassword(
               _emailController.text.trim(), 
               _codeController.text.trim(),
               _newPasswordController.text.trim()
            );
            setState(() => _isLoading = false);

            if (result['success'] == true) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Contraseña actualizada', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
               setState(() => _currentView = AuthView.login);
            } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Error al restablecer', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
            }
        }),
        SizedBox(height: 24),

        TextButton(
          onPressed: () => setState(() => _currentView = AuthView.login),
          child: Text('Volver al Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // --- Components ---

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF333333),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.grey[500]),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Color(0xFFD30000),
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActionButton({required String text, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFFD30000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: _isLoading
            ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(text, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Por favor llena todos los campos')));
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String? error = await authProvider.login(username, password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error), 
        backgroundColor: Colors.red
      ));
    }
  }
}

// --- Particle System ---
class Particle {
  double x;
  double y;
  double speed;
  double radius;
  double opacity;

  Particle({required this.x, required this.y, required this.speed, required this.radius, required this.opacity});

  void update() {
    y += speed;
    if (y > 1.0) {
      y = 0.0;
      x = Random().nextDouble();
    }
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Color(0xFFD30000);
    for (var p in particles) {
      paint.color = Color(0xFFD30000).withOpacity(p.opacity);
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
