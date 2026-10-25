import 'package:flutter/material.dart';

import '../theme.dart';

class NavItem {
  const NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Barre de navigation : 4 destinations et, au centre, une action dorée.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.onCenter,
    this.centerLabel = 'Nouvelle discussion',
    this.badges = const {},
  });

  /// Exactement 4 éléments : 2 à gauche, 2 à droite de l'action centrale.
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCenter;
  final String centerLabel;
  final Map<int, int> badges;

  Widget _item(int i) {
    final it = items[i];
    final sel = i == index;
    final color = sel ? AppColors.primary : AppColors.muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        label: it.label,
        child: InkWell(
          onTap: () => onSelect(i),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: AppSpacing.fast,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.primary.withOpacity(0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Badge(
                    isLabelVisible: (badges[i] ?? 0) > 0,
                    label: Text('${badges[i] ?? 0}'),
                    child: Icon(sel ? it.selectedIcon : it.icon,
                        color: color, size: 24),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: Colors.black54,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  _item(0),
                  _item(1),
                  const SizedBox(width: 76),
                  _item(2),
                  _item(3),
                ],
              ),
              Positioned(
                top: -18,
                left: 0,
                right: 0,
                child: Center(
                  child: Semantics(
                    button: true,
                    label: centerLabel,
                    child: Tooltip(
                      message: centerLabel,
                      child: GestureDetector(
                        onTap: onCenter,
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.gold,
                            border:
                                Border.all(color: AppColors.surface, width: 4),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 8,
                                  offset: Offset(0, 3)),
                            ],
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: AppColors.deepGreen, size: 26),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
