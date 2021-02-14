library emoji_picker;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:emoji_picker/emoji_picker.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:math';
import '../emoji_lists.dart' as emojiList;

import 'package:shared_preferences/shared_preferences.dart';

/// Callback function for when emoji is selected
///
/// The function returns the selected [Emoji] as well as the [Category] from which it originated
typedef void OnEmojiSelected(Emoji emoji);

const kEmojiCacheKey = 'emoji_cache_';
const kRecentEmojisKey = 'recent_emojis';

const _indexToCategory = {
  0: Category.RECENT,
  1: Category.SMILEYS,
  2: Category.ANIMALS,
  3: Category.FOODS,
  4: Category.TRAVEL,
  5: Category.ACTIVITIES,
  6: Category.OBJECTS,
  7: Category.SYMBOLS,
  8: Category.FLAGS,
};

/// The Emoji Keyboard widget
///
/// This widget displays a grid of [Emoji] sorted by [Category] which the user can horizontally scroll through.
///
/// There is also a bottombar which displays all the possible [Category] and allow the user to quickly switch to that [Category]
class EmojiPicker extends StatefulWidget {
  @override
  _EmojiPickerState createState() => new _EmojiPickerState();

  /// Number of columns in keyboard grid
  final int columns;

  /// Number of rows in keyboard grid
  final int rows;

  /// The function called when the emoji is selected
  final OnEmojiSelected onEmojiSelected;

  /// The background color of the keyboard
  final Color bgColor;

  /// The color of the keyboard page indicator
  final Color indicatorColor;

  final Color progressIndicatorColor;

  /// The string to be displayed if no recent emojis to display
  final String noRecentsText;

  /// The text style for the [noRecentsText]
  final TextStyle noRecentsStyle;

  /// Determines the icon to display for each [Category]
  final CategoryIcons categoryIcons;

  /// size of icon
  final double iconSize;

  /// grid factor
  final double gridFactor;

  final List<String> fontFamilyFallback;

  EmojiPicker({
    Key key,
    @required this.onEmojiSelected,
    this.columns = 7,
    this.rows = 3,
    this.gridFactor = 1.3,
    this.iconSize = 24,
    this.bgColor,
    this.indicatorColor = Colors.blue,
    this.progressIndicatorColor = Colors.blue,
    this.noRecentsText = 'Keine kürzliche benutzten',
    TextStyle noRecentsStyle,
    CategoryIcons categoryIcons,
    this.fontFamilyFallback,
  })  : this.categoryIcons = categoryIcons ?? CategoryIcons(),
        this.noRecentsStyle =
            noRecentsStyle ?? TextStyle(fontSize: 20, color: Colors.black26),
        super(key: key);
}

/// A class to store data for each individual emoji
class Emoji extends Equatable {
  /// The name or description for this emoji
  final String name;

  /// The unicode string for this emoji
  ///
  /// This is the string that should be displayed to view the emoji
  final String emoji;

  Emoji({@required this.name, @required this.emoji});

  String toJsonString() => json.encode({'n': name, 'e': emoji});

  static Emoji fromJsonString(String jsonString) {
    final js = json.decode(jsonString);
    return Emoji(name: js['n'], emoji: js['e']);
  }

  @override
  String toString() {
    return 'Name: ' + name + ', Emoji: ' + emoji;
  }

  @override
  List<Object> get props => [name, emoji];
}

class _EmojiPickerState extends State<EmojiPicker>
    with SingleTickerProviderStateMixin {
  static const _platform = const MethodChannel('emoji_picker');

  List<Emoji> _recentEmojis = [];

  ItemScrollController scrollListController = ItemScrollController();
  ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();

  TabController _categoryTabController;

  Map<Category, Map<String, String>> _cacheMap = Map();

  @override
  void initState() {
    _createTabBar();
    _getRecentEmojis().then((recentEmojis) {
      _recentEmojis = recentEmojis;
      if (mounted) {
        setState(() {});
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _categoryTabController.dispose();
    super.dispose();
  }

  void _createTabBar() {
    if (_categoryTabController == null) {
      _categoryTabController =
          TabController(length: 9, vsync: this, initialIndex: 0);
    }
    itemPositionsListener.itemPositions.addListener(() {
      if (itemPositionsListener.itemPositions.value.isNotEmpty) {
        final indexList =
            itemPositionsListener.itemPositions.value.map((e) => e.index);
        //final maxIndex = indexList.reduce(max);
        final minIndex = indexList.reduce(min);

        _categoryTabController.animateTo(minIndex);
      }
    });
  }

  Future<Map<String, String>> _getFiltered(Map<String, String> emoji) async {
    if (!Platform.isAndroid) {
      debugPrint('This function should only be called on platform Android!');
      return emoji;
    }
    try {
      Map<dynamic, dynamic> temp =
          await _platform.invokeMethod('checkAvailability', {'emoji': emoji});
      final Map<String, String> copy = Map.from(emoji);
      copy.removeWhere((key, _) => !temp.containsKey(key));
      debugPrint(
          'copy contains ${copy.length} emojis out of ${emoji.length} original emojis.');
      return copy;
      // return copy..removeWhere((key, _) => !temp.containsKey(key));
    } on PlatformException catch (e) {
      print(e);
      return emoji;
    }
  }

  Future<List<Emoji>> _getRecentEmojis() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs
            .getStringList(kRecentEmojisKey)
            ?.map<Emoji>(Emoji.fromJsonString)
            ?.toList() ??
        [];
  }

  void addRecentEmoji(Emoji emoji) async {
    final prefs = await SharedPreferences.getInstance();
    _recentEmojis.removeWhere((element) => element == emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 30) {
      _recentEmojis = _recentEmojis.take(30);
    }
    prefs.setStringList(kRecentEmojisKey,
        _recentEmojis.map((e) => e.toJsonString()).toList(growable: false));
  }

  Future<Map<String, String>> _getAvailableEmojis(Category category) async {
    if (kIsWeb || !Platform.isAndroid) return _emojiMapForCategory(category);
    final cachedMap = _cacheMap[category];
    if (cachedMap != null) {
      return cachedMap;
    }
    final newCachedMap = await _getFiltered(_emojiMapForCategory(category));
    _cacheMap[category] = newCachedMap;
    return newCachedMap;
  }

  Widget _emojiIcon(String emojiChar, Function onSelected) {
    return Center(
        child: GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: EdgeInsets.all(0),
        //color: widget.bgColor,
        child: Center(
          child: Text(
            emojiChar,
            style: TextStyle(
              fontSize: widget.iconSize,
              fontFamily: kIsWeb ? 'NotoColorEmoji' : null,
              fontFamilyFallback: widget.fontFamilyFallback,
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildCategory(Category category) {
    return FutureBuilder<Map<String, String>>(
        future: _getAvailableEmojis(category),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _gridCategory(snapshot.data, category);
          }
          return _gridCategory(_emojiMapForCategory(category), category);
        });
  }

  Map<String, String> _emojiMapForCategory(Category category) {
    switch (category) {
      case Category.RECENT:
        return null;
      case Category.SMILEYS:
        return emojiList.smileys;
      case Category.ANIMALS:
        return emojiList.animals;
      case Category.FOODS:
        return emojiList.foods;
      case Category.TRAVEL:
        return emojiList.travel;
      case Category.ACTIVITIES:
        return emojiList.activities;
      case Category.OBJECTS:
        return emojiList.objects;
      case Category.SYMBOLS:
        return emojiList.symbols;
      case Category.FLAGS:
        return emojiList.flags;
    }
    return null;
  }

  Widget _gridCategory(Map<String, String> itemMap, Category category) {
    return Container(
      key: Key(category.toString()),
      child: Column(
        children: [
          GridView.count(
            children: itemMap.entries
                .map<Widget>((mapEntry) => _emojiIcon(mapEntry.value, () {
                      final emoji = Emoji(
                        name: mapEntry.key,
                        emoji: mapEntry.value,
                      );
                      widget.onEmojiSelected(emoji);
                      addRecentEmoji(emoji);
                    }))
                .toList(),
            shrinkWrap: true,
            scrollDirection: Axis.vertical,
            crossAxisCount: widget.columns,
            physics: ClampingScrollPhysics(),
          ),
        ],
      ),
    );
  }

  Widget recentPage() {
    if (_recentEmojis.length > 0) {
      return Container(
        color: widget.bgColor,
        child: GridView.count(
          shrinkWrap: true,
          primary: true,
          crossAxisCount: widget.columns,
          children: _recentEmojis
              .map((emoji) => _emojiIcon(emoji.emoji, () {
                    widget.onEmojiSelected(
                      emoji,
                    );
                  }))
              .toList(growable: false),
        ),
      );
    } else {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          widget.noRecentsText,
          style: Theme.of(context).textTheme.caption,
        ),
      ));
    }
  }

  Widget defaultButton(CategoryIcon categoryIcon) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 9,
      height: MediaQuery.of(context).size.width / 9,
      child: Container(
        color: widget.bgColor,
        child: Center(
          child: Icon(
            categoryIcon.icon,
            size: 22,
            color: categoryIcon.color,
          ),
        ),
      ),
    );
  }

  Widget scrollableMainPanel() {
    return ScrollablePositionedList.builder(
      initialScrollIndex: 1,
      itemCount: 9,
      itemScrollController: scrollListController,
      itemPositionsListener: itemPositionsListener,
      itemBuilder: (context, index) {
        if (index == 0) {
          debugPrint('building recent page');
          return Column(
            children: [
              recentPage(),
              Divider(),
            ],
          );
        }
        final category = _indexToCategory[index];
        debugPrint('Building category $category for index $index');
        return Column(
          children: [
            _buildCategory(category),
            if (index < 9) Divider(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: scrollableMainPanel(),
        ),
        _categoryButtons()
      ],
    );
  }

  Widget _categoryButtons() {
    return TabBar(
      tabs: [
        _tabBarButton(Category.RECENT, widget.categoryIcons.recentIcon),
        _tabBarButton(Category.SMILEYS, widget.categoryIcons.smileyIcon),
        _tabBarButton(Category.ANIMALS, widget.categoryIcons.animalIcon),
        _tabBarButton(Category.FOODS, widget.categoryIcons.foodIcon),
        _tabBarButton(Category.TRAVEL, widget.categoryIcons.travelIcon),
        _tabBarButton(Category.ACTIVITIES, widget.categoryIcons.activityIcon),
        _tabBarButton(Category.OBJECTS, widget.categoryIcons.objectIcon),
        _tabBarButton(Category.SYMBOLS, widget.categoryIcons.symbolIcon),
        _tabBarButton(Category.FLAGS, widget.categoryIcons.flagIcon),
      ],
      indicatorSize: TabBarIndicatorSize.tab,
      unselectedLabelColor: Colors.white,
      controller: _categoryTabController,
      indicatorColor: widget.indicatorColor,
      labelPadding: EdgeInsets.symmetric(vertical: 5),
      onTap: (index) {
        scrollListController.scrollTo(
            index: index, duration: Duration(milliseconds: 500));
      },
    );
  }

  Widget _tabBarButton(Category category, CategoryIcon icon) {
    return Container(
      padding: EdgeInsets.all(0),
      alignment: Alignment.center,
      child: Icon(icon.icon, size: 22, color: icon.color),
    );
  }
}
