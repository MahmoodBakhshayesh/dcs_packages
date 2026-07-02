import 'package:flutter/material.dart';

import 'dcs_device_controller.dart';
import 'dcs_models.dart';

typedef DcsDeviceStatusBuilder =
    Widget Function(
      BuildContext context,
      Map<String, DcsDeviceStatus> statuses,
    );

/// Rebuilds whenever device status changes.
class DcsDeviceStatusBuilderWidget extends StatelessWidget {
  const DcsDeviceStatusBuilderWidget({
    super.key,
    required this.statuses,
    required this.builder,
    this.initialStatuses = const {},
  });

  final Stream<Map<String, DcsDeviceStatus>> statuses;
  final Map<String, DcsDeviceStatus> initialStatuses;
  final DcsDeviceStatusBuilder builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, DcsDeviceStatus>>(
      stream: statuses,
      initialData: initialStatuses,
      builder: (context, snapshot) {
        return builder(context, snapshot.data ?? const {});
      },
    );
  }
}

/// Controller-bound status list. Drop this into a page after creating a controller.
class DcsDeviceControllerStatusList extends StatelessWidget {
  const DcsDeviceControllerStatusList({
    super.key,
    required this.controller,
    this.showReconnectButtons = true,
  });

  final DcsDeviceController controller;
  final bool showReconnectButtons;

  @override
  Widget build(BuildContext context) {
    return DcsDeviceStatusList(
      statuses: controller.statuses,
      initialStatuses: controller.currentStatuses,
      profiles: controller.profiles,
      onReconnect: showReconnectButtons ? controller.reconnect : null,
    );
  }
}

/// Controller-bound grid for dashboards and setup screens.
class DcsDeviceStatusGrid extends StatelessWidget {
  const DcsDeviceStatusGrid({
    super.key,
    required this.controller,
    this.crossAxisCount = 3,
    this.spacing = 12,
    this.runSpacing = 12,
    this.showReconnectButtons = true,
  });

  final DcsDeviceController controller;
  final int crossAxisCount;
  final double spacing;
  final double runSpacing;
  final bool showReconnectButtons;

  @override
  Widget build(BuildContext context) {
    return DcsDeviceStatusBuilderWidget(
      statuses: controller.statuses,
      initialStatuses: controller.currentStatuses,
      builder: (context, statuses) {
        if (controller.profiles.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final effectiveCount = crossAxisCount.clamp(
              1,
              controller.profiles.length,
            );
            final itemWidth =
                (width - (spacing * (effectiveCount - 1))) / effectiveCount;

            return Wrap(
              spacing: spacing,
              runSpacing: runSpacing,
              children: [
                for (final profile in controller.profiles)
                  SizedBox(
                    width: itemWidth,
                    child: DcsDeviceStatusCard(
                      profile: profile,
                      status:
                          statuses[profile.id] ??
                          DcsDeviceStatus.initial(profile.id),
                      onReconnect: showReconnectButtons
                          ? () => controller.reconnect(profile.id)
                          : null,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Compact dashboard summary for all configured devices.
class DcsDeviceStatusSummaryBanner extends StatelessWidget {
  const DcsDeviceStatusSummaryBanner({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.all(12),
  });

  final DcsDeviceController controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DcsDeviceStatusBuilderWidget(
      statuses: controller.statuses,
      initialStatuses: controller.currentStatuses,
      builder: (context, statuses) {
        final total = controller.profiles.length;
        final ready = statuses.values
            .where((status) => status.isConnected)
            .length;
        final attention = statuses.values
            .where((status) => status.needsAttention)
            .length;
        final color = attention > 0
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Icon(attention > 0 ? Icons.warning_amber : Icons.check_circle),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    attention > 0
                        ? '$attention of $total device(s) need attention'
                        : '$ready of $total device(s) ready',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Simple ready-to-use status list for desktop DCS utility panels.
class DcsDeviceStatusList extends StatelessWidget {
  const DcsDeviceStatusList({
    super.key,
    required this.statuses,
    this.profiles = const [],
    this.initialStatuses = const {},
    this.onReconnect,
  });

  final Stream<Map<String, DcsDeviceStatus>> statuses;
  final Map<String, DcsDeviceStatus> initialStatuses;
  final List<DcsDeviceProfile> profiles;
  final ValueChanged<String>? onReconnect;

  @override
  Widget build(BuildContext context) {
    return DcsDeviceStatusBuilderWidget(
      statuses: statuses,
      initialStatuses: initialStatuses,
      builder: (context, statuses) {
        final ids = profiles.isEmpty
            ? statuses.keys.toList(growable: false)
            : profiles.map((profile) => profile.id).toList(growable: false);

        return ListView.separated(
          shrinkWrap: true,
          itemCount: ids.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final profileId = ids[index];
            final profile = _profileFor(profileId);
            final status =
                statuses[profileId] ?? DcsDeviceStatus.initial(profileId);
            return DcsDeviceStatusTile(
              status: status,
              label: profile?.label ?? profileId,
              kind: profile?.kind,
              onReconnect: onReconnect == null
                  ? null
                  : () => onReconnect!(profileId),
            );
          },
        );
      },
    );
  }

  DcsDeviceProfile? _profileFor(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

/// Card-style view for one configured DCS device.
class DcsDeviceStatusCard extends StatelessWidget {
  const DcsDeviceStatusCard({
    super.key,
    required this.profile,
    required this.status,
    this.onReconnect,
    this.imageSize = 96,
  });

  final DcsDeviceProfile profile;
  final DcsDeviceStatus status;
  final VoidCallback? onReconnect;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForState(theme, status.state);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: DcsDeviceStatusImage(
                kind: profile.kind,
                state: status.state,
                size: imageSize,
              ),
            ),
            const SizedBox(height: 12),
            Text(profile.label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatusDot(color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.message ?? status.state.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (status.device != null) ...[
              const SizedBox(height: 8),
              Text(status.device!.portName, style: theme.textTheme.bodySmall),
            ],
            if (onReconnect != null && status.needsAttention) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onReconnect,
                  child: const Text('Reconnect'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DcsDeviceStatusTile extends StatelessWidget {
  const DcsDeviceStatusTile({
    super.key,
    required this.status,
    required this.label,
    this.kind,
    this.onReconnect,
    this.imageSize = 44,
  });

  final DcsDeviceStatus status;
  final String label;
  final DcsDeviceKind? kind;
  final VoidCallback? onReconnect;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForState(theme, status.state);

    return ListTile(
      leading: DcsDeviceStatusImage(
        kind: kind,
        state: status.state,
        size: imageSize,
      ),
      title: Text(label),
      subtitle: Text(status.message ?? status.state.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: status.updatedAt.toIso8601String(),
            child: _StatusDot(color: color),
          ),
          if (onReconnect != null && status.needsAttention) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onReconnect, child: const Text('Reconnect')),
          ],
        ],
      ),
    );
  }
}

/// Displays the packaged PNG that matches a device kind and connection state.
class DcsDeviceStatusImage extends StatelessWidget {
  const DcsDeviceStatusImage({
    super.key,
    required this.state,
    this.kind,
    this.size = 56,
    this.fit = BoxFit.contain,
  });

  final DcsDeviceKind? kind;
  final DcsDeviceConnectionState state;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      DcsDeviceStatusAssets.pathFor(kind: kind, state: state),
      package: DcsDeviceStatusAssets.packageName,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        final color = _colorForState(Theme.of(context), state);
        return Icon(_iconForKind(kind), color: color, size: size * 0.7);
      },
    );
  }
}

/// Asset-name resolver for the bundled DCS device status images.
class DcsDeviceStatusAssets {
  const DcsDeviceStatusAssets._();

  static const packageName = 'dcs_device_util';
  static const basePath = 'assets/devices';

  static String pathFor({
    required DcsDeviceConnectionState state,
    DcsDeviceKind? kind,
  }) {
    return '$basePath/${_deviceName(kind)}_${_statusName(state)}.png';
  }

  static String _deviceName(DcsDeviceKind? kind) {
    return switch (kind) {
      DcsDeviceKind.printer => 'dcs_printer',
      DcsDeviceKind.reader => 'dcs_reader',
      DcsDeviceKind.unknown || null => 'dcs_usb',
    };
  }

  static String _statusName(DcsDeviceConnectionState state) {
    return switch (state) {
      DcsDeviceConnectionState.connected ||
      DcsDeviceConnectionState.available => 'ready',
      DcsDeviceConnectionState.discovering ||
      DcsDeviceConnectionState.connecting ||
      DcsDeviceConnectionState.retrying ||
      DcsDeviceConnectionState.degraded => 'warning',
      DcsDeviceConnectionState.failed => 'error',
      DcsDeviceConnectionState.disconnected ||
      DcsDeviceConnectionState.unconfigured => 'offline',
    };
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 12, height: 12),
    );
  }
}

IconData _iconForKind(DcsDeviceKind? kind) {
  return switch (kind) {
    DcsDeviceKind.reader => Icons.credit_card,
    DcsDeviceKind.printer => Icons.print,
    DcsDeviceKind.unknown || null => Icons.usb,
  };
}

Color _colorForState(ThemeData theme, DcsDeviceConnectionState state) {
  return switch (state) {
    DcsDeviceConnectionState.connected => Colors.green,
    DcsDeviceConnectionState.available ||
    DcsDeviceConnectionState.connecting ||
    DcsDeviceConnectionState.discovering ||
    DcsDeviceConnectionState.retrying => theme.colorScheme.primary,
    DcsDeviceConnectionState.degraded => Colors.orange,
    DcsDeviceConnectionState.failed => theme.colorScheme.error,
    DcsDeviceConnectionState.disconnected ||
    DcsDeviceConnectionState.unconfigured => theme.disabledColor,
  };
}
