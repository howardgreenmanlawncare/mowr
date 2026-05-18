import 'package:flutter/material.dart';

void main() {
  runApp(const MowrApp());
}

class MowrApp extends StatelessWidget {
  const MowrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MOWR',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8F5),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF7F8F5),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: const MowrBookingDemo(),
    );
  }
}

class MowrBookingDemo extends StatefulWidget {
  const MowrBookingDemo({super.key});

  @override
  State<MowrBookingDemo> createState() => _MowrBookingDemoState();
}

class _MowrBookingDemoState extends State<MowrBookingDemo> {
  int _step = 0;

  final List<String> _stepLabels = const [
    'Postcode',
    'Address',
    'Lawn',
    'Access',
    'Photos',
    'Time',
    'Price',
    'Done',
  ];

  void _next() {
    if (_step < _stepLabels.length - 1) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _stepLabels[_step];

    return Scaffold(
      appBar: AppBar(
        leading: _step == 0
            ? null
            : IconButton(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Column(
          children: [
            Text(
              'MOWR',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                fontSize: 14,
              ),
            ),
            Text(
              'Book a lawn mow',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: Color(0xFFE7F2E8),
              child: Icon(Icons.grass_rounded, color: Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _step == _stepLabels.length - 1
          ? const MowrBottomNavigation()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: FilledButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(_buttonText),
                ),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: BookingProgress(
                step: _step,
                totalSteps: _stepLabels.length,
                label: title,
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: _screenForStep(_step),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _buttonText {
    switch (_step) {
      case 0:
        return 'Find address';
      case 5:
        return 'See price';
      case 6:
        return 'Pay and request booking';
      default:
        return 'Continue';
    }
  }

  Widget _screenForStep(int step) {
    switch (step) {
      case 0:
        return const PostcodeMaterialScreen();
      case 1:
        return const AddressMaterialScreen();
      case 2:
        return const LawnDetailsMaterialScreen();
      case 3:
        return const AccessExtrasMaterialScreen();
      case 4:
        return const PhotoUploadMaterialScreen();
      case 5:
        return const PreferredTimeMaterialScreen();
      case 6:
        return const PriceReviewMaterialScreen();
      case 7:
        return const ConfirmationMaterialScreen();
      default:
        return const PostcodeMaterialScreen();
    }
  }
}

class BookingProgress extends StatelessWidget {
  const BookingProgress({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.label,
  });

  final int step;
  final int totalSteps;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(
              '${step + 1} of $totalSteps',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: Colors.grey.shade200,
        ),
      ],
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 30),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
                height: 1.45,
              ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class PostcodeMaterialScreen extends StatelessWidget {
  const PostcodeMaterialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.location_on_rounded,
          title: 'Where is the lawn?',
          subtitle: 'Enter the property postcode so we can check if mowing is available in your area.',
        ),
        TextField(
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Postcode',
            hintText: 'Example: CM1 1AA',
            suffixIcon: Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          controller: TextEditingController(text: 'CM1 1AA'),
        ),
        const SizedBox(height: 16),
        InfoCard(
          icon: Icons.check_circle_rounded,
          title: 'Good news',
          body: 'We cover this area. You can continue and request a mow.',
          tint: Theme.of(context).colorScheme.primaryContainer,
        ),
      ],
    );
  }
}

class AddressMaterialScreen extends StatelessWidget {
  const AddressMaterialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.home_rounded,
          title: 'Select the address',
          subtitle: 'Choose the right property and add anything the mower should know before arriving.',
        ),
        const SelectionCard(
          selected: true,
          icon: Icons.location_on_rounded,
          title: '14 Meadow View',
          subtitle: 'Chelmsford, CM1 1AA',
        ),
        const SizedBox(height: 12),
        const SelectionCard(
          selected: false,
          icon: Icons.location_on_outlined,
          title: '16 Meadow View',
          subtitle: 'Chelmsford, CM1 1AA',
        ),
        const SizedBox(height: 22),
        TextField(
          minLines: 4,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Access notes',
            hintText: 'Gate code, side entrance, parking, dog in garden, etc.',
            alignLabelWithHint: true,
          ),
          controller: TextEditingController(
            text: 'Side gate is on the left. Please shut the gate after mowing.',
          ),
        ),
      ],
    );
  }
}

class LawnDetailsMaterialScreen extends StatefulWidget {
  const LawnDetailsMaterialScreen({super.key});

  @override
  State<LawnDetailsMaterialScreen> createState() => _LawnDetailsMaterialScreenState();
}

class _LawnDetailsMaterialScreenState extends State<LawnDetailsMaterialScreen> {
  Set<String> lawnAreas = {'front', 'back'};
  String size = 'medium';
  String length = 'normal';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.grass_rounded,
          title: 'Tell us about the lawn',
          subtitle: 'This helps us give a fair price and avoid surprises on the day.',
        ),
        Text('Which areas need mowing?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          multiSelectionEnabled: true,
          segments: const [
            ButtonSegment(value: 'front', label: Text('Front'), icon: Icon(Icons.yard_rounded)),
            ButtonSegment(value: 'back', label: Text('Back'), icon: Icon(Icons.forest_rounded)),
          ],
          selected: lawnAreas,
          onSelectionChanged: (value) => setState(() => lawnAreas = value),
        ),
        const SizedBox(height: 28),
        Text('Rough size', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: const Text('Small'),
              selected: size == 'small',
              onSelected: (_) => setState(() => size = 'small'),
            ),
            ChoiceChip(
              label: const Text('Medium'),
              selected: size == 'medium',
              onSelected: (_) => setState(() => size = 'medium'),
            ),
            ChoiceChip(
              label: const Text('Large'),
              selected: size == 'large',
              onSelected: (_) => setState(() => size = 'large'),
            ),
            ChoiceChip(
              label: const Text('Very large / not sure'),
              selected: size == 'not_sure',
              onSelected: (_) => setState(() => size = 'not_sure'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Grass length', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Column(
          children: [
            RadioListTile<String>(
              value: 'normal',
              groupValue: length,
              onChanged: (value) => setState(() => length = value!),
              title: const Text('Normal'),
              subtitle: const Text('Recently maintained'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              tileColor: Colors.white,
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'long',
              groupValue: length,
              onChanged: (value) => setState(() => length = value!),
              title: const Text('Long'),
              subtitle: const Text('Longer than usual, but manageable'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              tileColor: Colors.white,
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'overgrown',
              groupValue: length,
              onChanged: (value) => setState(() => length = value!),
              title: const Text('Very long / overgrown'),
              subtitle: const Text('May need manual review'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              tileColor: Colors.white,
            ),
          ],
        ),
      ],
    );
  }
}

class AccessExtrasMaterialScreen extends StatefulWidget {
  const AccessExtrasMaterialScreen({super.key});

  @override
  State<AccessExtrasMaterialScreen> createState() => _AccessExtrasMaterialScreenState();
}

class _AccessExtrasMaterialScreenState extends State<AccessExtrasMaterialScreen> {
  bool wasteRemoval = true;
  bool lockedGate = false;
  bool steps = false;
  bool narrowAccess = false;
  String access = 'straightforward';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.lock_open_rounded,
          title: 'Access and extras',
          subtitle: 'Tell us if anything might make access more difficult for the mower.',
        ),
        Text('Access type', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        RadioListTile<String>(
          value: 'straightforward',
          groupValue: access,
          onChanged: (value) => setState(() => access = value!),
          title: const Text('Straightforward access'),
          subtitle: const Text('Normal side or front access'),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          value: 'restricted',
          groupValue: access,
          onChanged: (value) => setState(() => access = value!),
          title: const Text('Restricted access'),
          subtitle: const Text('Adds a small access fee'),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          value: 'no_side_access',
          groupValue: access,
          onChanged: (value) => setState(() => access = value!),
          title: const Text('No side access'),
          subtitle: const Text('This may need manual review'),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: lockedGate,
                onChanged: (value) => setState(() => lockedGate = value),
                title: const Text('Locked gate'),
                subtitle: const Text('Customer should provide access notes'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: steps,
                onChanged: (value) => setState(() => steps = value),
                title: const Text('Steps'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: narrowAccess,
                onChanged: (value) => setState(() => narrowAccess = value),
                title: const Text('Narrow access'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: wasteRemoval,
                onChanged: (value) => setState(() => wasteRemoval = value),
                title: const Text('Take clippings away'),
                subtitle: const Text('Adds waste removal to the booking'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PhotoUploadMaterialScreen extends StatelessWidget {
  const PhotoUploadMaterialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.add_a_photo_rounded,
          title: 'Add lawn photos',
          subtitle: 'Photos are optional for the first version, but they help the mower avoid surprises.',
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: const [
            UploadTile(label: 'Front lawn'),
            UploadTile(label: 'Back lawn'),
            UploadTile(label: 'Side access'),
            UploadTile(label: 'Other area'),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continue without photos'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ],
    );
  }
}

class PreferredTimeMaterialScreen extends StatefulWidget {
  const PreferredTimeMaterialScreen({super.key});

  @override
  State<PreferredTimeMaterialScreen> createState() => _PreferredTimeMaterialScreenState();
}

class _PreferredTimeMaterialScreenState extends State<PreferredTimeMaterialScreen> {
  int selectedDay = 1;
  String selectedWindow = 'afternoon';

  final days = const [
    ('Today', '17'),
    ('Tomorrow', '18'),
    ('Tue', '19'),
    ('Wed', '20'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.calendar_month_rounded,
          title: 'Preferred time',
          subtitle: 'Choose a preferred day and window. We’ll confirm once a mower accepts the job.',
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final selected = selectedDay == index;
              final day = days[index];

              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => selectedDay = index),
                label: SizedBox(
                  width: 76,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(day.$1, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        day.$2,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        TimeWindowCard(
          selected: selectedWindow == 'morning',
          icon: Icons.wb_sunny_rounded,
          title: 'Morning',
          subtitle: '8am to 12pm',
          onTap: () => setState(() => selectedWindow = 'morning'),
        ),
        const SizedBox(height: 10),
        TimeWindowCard(
          selected: selectedWindow == 'afternoon',
          icon: Icons.light_mode_rounded,
          title: 'Afternoon',
          subtitle: '12pm to 4pm',
          onTap: () => setState(() => selectedWindow = 'afternoon'),
        ),
        const SizedBox(height: 10),
        TimeWindowCard(
          selected: selectedWindow == 'evening',
          icon: Icons.nights_stay_rounded,
          title: 'Evening',
          subtitle: '4pm to 7pm',
          onTap: () => setState(() => selectedWindow = 'evening'),
        ),
      ],
    );
  }
}

class PriceReviewMaterialScreen extends StatelessWidget {
  const PriceReviewMaterialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenHeader(
          icon: Icons.payments_rounded,
          title: 'Review and price',
          subtitle: 'Here is the fixed price based on the details you gave us.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const PriceRow(label: 'Medium lawn', detail: 'Front and back', amount: '£35'),
                const PriceRow(label: 'Normal grass', detail: 'No long grass fee', amount: '£0'),
                const PriceRow(label: 'Straightforward access', detail: 'No access fee', amount: '£0'),
                Divider(height: 34, color: Colors.grey.shade200),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    Text('£35', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          icon: Icons.lock_rounded,
          title: 'Secure payment',
          body: 'In the live version, payment will be taken securely before the booking is assigned.',
          tint: Theme.of(context).colorScheme.secondaryContainer,
        ),
      ],
    );
  }
}

class ConfirmationMaterialScreen extends StatelessWidget {
  const ConfirmationMaterialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 42),
        CircleAvatar(
          radius: 54,
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.check_rounded, size: 62, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(height: 28),
        Text(
          'Booking requested',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Text(
          'We’ve received the mowing request. We’ll assign a local mower and send an update once the job is accepted.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700, height: 1.45),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: const [
                StatusLine(icon: Icons.schedule_rounded, title: 'Awaiting assignment', subtitle: 'Tomorrow, afternoon'),
                Divider(height: 28),
                StatusLine(icon: Icons.location_on_rounded, title: '14 Meadow View', subtitle: 'Chelmsford, CM1 1AA'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('View booking details'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ],
    );
  }
}

class SelectionCard extends StatelessWidget {
  const SelectionCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.55) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected ? colorScheme.primary : Colors.grey.shade200,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? colorScheme.primary : Colors.grey.shade600),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: selected ? Icon(Icons.check_circle_rounded, color: colorScheme.primary) : null,
      ),
    );
  }
}

class UploadTile extends StatelessWidget {
  const UploadTile({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.add_a_photo_rounded, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class TimeWindowCard extends StatelessWidget {
  const TimeWindowCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: selected ? colorScheme.primary : Colors.grey.shade200, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: selected ? colorScheme.primary : Colors.grey.shade100,
                child: Icon(icon, color: selected ? colorScheme.onPrimary : Colors.grey.shade700),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
              ),
              Radio<bool>(
                value: true,
                groupValue: selected,
                onChanged: (_) => onTap(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tint,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(color: Colors.grey.shade800, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.label,
    required this.detail,
    required this.amount,
  });

  final String label;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(detail, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

class MowrBottomNavigation extends StatelessWidget {
  const MowrBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Bookings'),
        NavigationDestination(icon: Icon(Icons.help_outline_rounded), selectedIcon: Icon(Icons.help_rounded), label: 'Help'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
      ],
    );
  }
}
