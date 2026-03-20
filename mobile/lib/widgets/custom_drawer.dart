import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/providers.dart';
import '../models/models.dart';

class CustomDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get user info from Provider (assumes AuthProvider has 'username')
    final authProvider = Provider.of<AuthProvider>(context);
    final username = authProvider.username ?? 'Usuario';

    return Drawer(
      backgroundColor: Color(0xFF0E0E0E),
      child: Column(
        children: [
          // Custom Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Color(0xFF0E0E0E), // Match drawer background
            ),
            padding: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${authProvider.profilePic}'),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          username,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getRoleColor(authProvider.userRole),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            authProvider.userRole.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.edit_square, color: Colors.white),
                  onPressed: () => _showEditUsernameDialog(context, authProvider),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Notificaciones', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                if (authProvider.userRole.toLowerCase() == 'admin')
                  IconButton(
                    icon: Icon(Icons.add, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () => _showAddNotificationDialog(context, Provider.of<NotificationProvider>(context, listen: false)),
                  ),
              ],
            ),
          ),
          Divider(color: Colors.grey[800]),

          Expanded(
            child: Consumer<NotificationProvider>(
              builder: (context, notifProv, child) {
                if (notifProv.isLoading && notifProv.notifications.isEmpty) {
                  return Center(child: CircularProgressIndicator(color: Color(0xFFE50914)));
                }
                if (notifProv.notifications.isEmpty) {
                  return Center(child: Text('No hay notificaciones', style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: notifProv.notifications.length,
                  itemBuilder: (context, index) {
                    return _buildNotificationItem(context, notifProv.notifications[index], authProvider, notifProv);
                  },
                );
              },
            ),
          ),

          // Logout Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await authProvider.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFD30000),
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(BuildContext context, Notificacion notif, AuthProvider auth, NotificationProvider notifProv) {
    IconData icon;
    Color iconBgColor;
    
    if (notif.type == 'alert') {
      icon = Icons.warning_amber_rounded;
      iconBgColor = Color(0xFF3B2020); // Dark red
    } else {
      icon = Icons.info_outline;
      iconBgColor = Color(0xFF1E2A38); // Dark blue
    }

    String _formatDate(String isoString) {
      try {
        DateTime parsed = DateTime.parse(isoString);
        DateTime utcDate = parsed.isUtc ? parsed : parsed.toUtc();
        DateTime cdmxDate = utcDate.subtract(Duration(hours: 6));
        
        String day = cdmxDate.day.toString().padLeft(2, '0');
        String month = cdmxDate.month.toString().padLeft(2, '0');
        String year = cdmxDate.year.toString();
        
        int hour = cdmxDate.hour;
        int minute = cdmxDate.minute;
        String ampm = hour >= 12 ? 'p.m.' : 'a.m.';
        
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        
        String minStr = minute.toString().padLeft(2, '0');
        
        return '$day/$month/$year $hour:$minStr $ampm';
      } catch (e) {
        return isoString;
      }
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: iconBgColor),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(notif.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                        if (auth.userRole.toLowerCase() == 'admin')
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Color(0xFF1E1E1E),
                                  title: Text('¿Borrar notificación?', style: TextStyle(color: Colors.white)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar', style: TextStyle(color: Colors.grey))),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Borrar', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                notifProv.deleteNotification(notif.id);
                              }
                            },
                            child: Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(notif.message, style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.4)),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                        SizedBox(width: 4),
                        Text(_formatDate(notif.createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(color: Colors.grey[900], height: 1),
      ],
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Color(0xFF6200EA); // Purple
      case 'premium':
        return Color(0xFFFFD700); // Gold
      default:
        return Colors.grey; // Free
    }
  }

  void _showEditUsernameDialog(BuildContext context, AuthProvider authProvider) {
    final TextEditingController _usernameController = TextEditingController(text: authProvider.username);
    final TextEditingController _passwordController = TextEditingController();
    bool _isLoading = false;
    String? _feedbackMessage;
    bool _isSuccess = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 8),
              contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actionsPadding: EdgeInsets.only(bottom: 24, right: 24, left: 24),
              title: Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/${authProvider.profilePic}'),
                        ),
                        GestureDetector(
                          onTap: () {
                            // Cierra el modal de edición para abrir el selector (o lo sobrepone)
                            Navigator.pop(context);
                            _showProfilePicSelectorDialog(context, authProvider);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Color(0xFFE50914),
                              shape: BoxShape.circle,
                              border: Border.all(color: Color(0xFF1E1E1E), width: 3),
                            ),
                            child: Icon(Icons.edit, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text(
                      authProvider.username ?? 'Usuario',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)
                    ),
                    Text(
                      authProvider.userRole.toUpperCase(),
                      style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(color: Colors.grey[800], height: 32),
                  Text(
                    'Puedes tocar el lápiz en tu foto para cambiarla.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Para cambiar tu nombre, ingresa uno nuevo (mínimo 4 letras) y confirma tu contraseña.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                      hintText: 'Nuevo nombre de usuario',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF404040)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914)), borderRadius: BorderRadius.circular(4)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                      hintText: 'Contraseña actual',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF404040)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914)), borderRadius: BorderRadius.circular(4)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  if (_feedbackMessage != null) ...[
                    SizedBox(height: 12),
                    Text(
                      _feedbackMessage!,
                      style: TextStyle(color: _isSuccess ? Colors.green : Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF404040),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Text('Cerrar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () async {
                          final newUsername = _usernameController.text.trim();
                          final password = _passwordController.text;

                          if (newUsername == authProvider.username && password.isEmpty) {
                             Navigator.pop(context);
                             return;
                          }

                          if (newUsername.length < 4) {
                            setState(() {
                              _feedbackMessage = "El nombre debe tener mínimo 4 caracteres.";
                              _isSuccess = false;
                            });
                            return;
                          }
                          if (password.isEmpty) {
                            setState(() {
                              _feedbackMessage = "Ingresa tu contraseña para cambiar el usuario.";
                              _isSuccess = false;
                            });
                            return;
                          }

                          setState(() {
                            _isLoading = true;
                            _feedbackMessage = "Guardando...";
                            _isSuccess = false;
                          });

                          final result = await authProvider.changeUsername(newUsername, password);
                          
                          if (context.mounted) {
                            setState(() {
                              _isLoading = false;
                              if (result['success'] == true) {
                                _isSuccess = true;
                                _feedbackMessage = "¡Actualizado correctamente!";
                                Future.delayed(Duration(seconds: 1), () {
                                  if (context.mounted) Navigator.pop(context);
                                });
                              } else {
                                _isSuccess = false;
                                _feedbackMessage = result['message'] ?? "Error desconocido";
                              }
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFE50914),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: _isLoading 
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showProfilePicSelectorDialog(BuildContext context, AuthProvider authProvider) {
    const List<String> profileImages = [
      "alucard.jpg", "chunchi.jpg", "daria.jpg", "elliot.jpg", "godz.jpg",
      "knight.jpg", "pennywise.jpg", "pirate.jpg", "princess.jpg", "superman.jpg"
    ];

    String _selectedTemporaryPic = authProvider.profilePic;
    bool _isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 16),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: EdgeInsets.all(24),
              title: Text('Selecciona una Foto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
              content: SizedBox(
                width: double.maxFinite,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: profileImages.length,
                  itemBuilder: (context, index) {
                    final imgFile = profileImages[index];
                    final isSelected = _selectedTemporaryPic == imgFile;

                    return GestureDetector(
                      onTap: () {
                        setState(() { _selectedTemporaryPic = imgFile; });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Color(0xFFE50914) : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.grey[800],
                          backgroundImage: NetworkImage('https://vnc-e.com/Multimedia/Profiles/$imgFile'),
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () {
                          Navigator.pop(context);
                          _showEditUsernameDialog(context, authProvider); // Volver al menú anterior
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF404040),
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Cancelar', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () async {
                          if (_selectedTemporaryPic == authProvider.profilePic) {
                            Navigator.pop(context);
                            _showEditUsernameDialog(context, authProvider);
                            return;
                          }

                          setState(() => _isSaving = true);
                          
                          final success = await authProvider.updateProfilePic(_selectedTemporaryPic);
                          
                          if (context.mounted) {
                            setState(() => _isSaving = false);
                            Navigator.pop(context);
                            // Volvemos a abrir el menú que veníamos usando, ahora con la foto nueva
                            _showEditUsernameDialog(context, authProvider);
                            
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Foto de perfil actualizada'), backgroundColor: Colors.green));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al conectarse a la nube'), backgroundColor: Colors.red));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFE50914),
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isSaving 
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Seleccionar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddNotificationDialog(BuildContext context, NotificationProvider notifProv) {
    final TextEditingController _titleController = TextEditingController();
    final TextEditingController _messageController = TextEditingController();
    String _selectedType = 'info';
    bool _isLoading = false;
    String? _feedbackMessage;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('Crear Notificación', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                      hintText: 'Título',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF404040)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914)), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    style: TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                      hintText: 'Mensaje',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF404040)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914)), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    dropdownColor: Color(0xFF2C2C2C),
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF2C2C2C),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF404040)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE50914)), borderRadius: BorderRadius.circular(4)),
                    ),
                    items: [
                      DropdownMenuItem(value: 'info', child: Text('Tip (Azul)')),
                      DropdownMenuItem(value: 'alert', child: Text('Alerta (Rojo)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedType = val);
                      }
                    },
                  ),
                  if (_feedbackMessage != null) ...[
                    SizedBox(height: 12),
                    Text(_feedbackMessage!, style: TextStyle(color: Colors.red, fontSize: 14)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () async {
                    if (_titleController.text.isEmpty || _messageController.text.isEmpty) {
                      setState(() => _feedbackMessage = 'Llene todos los campos');
                      return;
                    }
                    setState(() {
                      _isLoading = true;
                      _feedbackMessage = null;
                    });
                    final success = await notifProv.createNotification(
                      _titleController.text,
                      _messageController.text,
                      _selectedType
                    );
                    if (context.mounted) {
                      if (success) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          _isLoading = false;
                          _feedbackMessage = 'Error al crear';
                        });
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE50914)),
                  child: _isLoading 
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Enviar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }
}
