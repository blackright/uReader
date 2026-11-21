import 'dart:convert';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as ast;

import '../../domain/books.dart';
import 'epub_limits.dart';

class CssElement {
  CssElement(this.tag, this.attributes, this.parent);
  final String tag;
  final Map<String, String> attributes;
  final CssElement? parent;
}

class ComputedVisibility {
  const ComputedVisibility({this.displayOff = false, this.visible = true});
  final bool displayOff, visible;
}

class _Rule {
  _Rule(
    this.selector,
    this.property,
    this.value,
    this.important,
    this.specificity,
    this.order,
  );
  final ast.Selector selector;
  final String property, value;
  final bool important;
  final int specificity, order;
}

/// Limited, explicit CSS profile; no execution, includes, URL loading or polyfill.
class SafeCss {
  final List<_Rule> _rules = [];
  int _bytes = 0, _selectors = 0, _evaluations = 0, _order = 0;
  final Set<String> warnings = {};
  int get byteCount => _bytes;
  int get selectorCount => _selectors;
  int get evaluationCount => _evaluations;
  void _guardComplexity(String source) {
    var depth = 0;
    for (final c in source.codeUnits) {
      if (c == 40 || c == 123 || c == 91) {
        if (++depth > EpubLimits.cssComplexity) {
          throw const BookFailure(BookError.limitExceeded);
        }
      } else if (c == 41 || c == 125 || c == 93) {
        depth--;
      }
    }
  }

  void add(String source) {
    if (source.length > EpubLimits.cssSheetBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final size = utf8.encode(source).length;
    _bytes += size;
    if (size > EpubLimits.cssSheetBytes || _bytes > EpubLimits.cssTotalBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    // Lexical bound before AST allocation. Parenthesis/braces depth is not delegated to csslib.
    _guardComplexity(source);
    final errors = <css.Message>[];
    final sheet = css.parse(source, errors: errors);
    if (errors.isNotEmpty) throw const BookFailure(BookError.invalidContent);
    for (final node in sheet.topLevels) {
      if (node is! ast.RuleSet) {
        warnings.add('unsupportedCss');
        continue;
      }
      for (final selector
          in node.selectorGroup?.selectors ?? <ast.Selector>[]) {
        if (++_selectors > EpubLimits.cssSelectors ||
            selector.simpleSelectorSequences.length >
                EpubLimits.cssComplexity) {
          throw const BookFailure(BookError.limitExceeded);
        }
        var specificity = 0;
        var supported = true;
        for (final seq in selector.simpleSelectorSequences) {
          final s = seq.simpleSelector;
          if (!(seq.isCombinatorNone ||
              seq.isCombinatorGreater ||
              seq.isCombinatorDescendant)) {
            supported = false;
          }
          if (s is ast.IdSelector) {
            specificity += 10000;
          } else if (s is ast.ClassSelector) {
            specificity += 100;
          } else if (s is ast.ElementSelector) {
            if (!s.isWildcard) specificity++;
          } else {
            supported = false;
          }
        }
        if (!supported) {
          warnings.add('unsupportedCss');
          continue;
        }
        for (final declaration
            in node.declarationGroup.declarations
                .whereType<ast.Declaration>()) {
          final property = declaration.property.toLowerCase();
          final value =
              declaration.expression?.span?.text.trim().toLowerCase() ?? '';
          if (property == 'display' &&
                  [
                    'none',
                    'block',
                    'inline',
                    'inline-block',
                    'list-item',
                    'table',
                    'table-row',
                    'table-cell',
                  ].contains(value) ||
              property == 'visibility' &&
                  ['visible', 'hidden', 'collapse'].contains(value)) {
            _rules.add(
              _Rule(
                selector,
                property,
                value,
                declaration.important,
                specificity,
                _order++,
              ),
            );
          } else {
            warnings.add('unsupportedCss');
          }
        }
      }
    }
  }

  bool _simple(ast.SimpleSelector selector, CssElement element) {
    if (++_evaluations > EpubLimits.selectorEvaluations) {
      throw const BookFailure(BookError.limitExceeded);
    }
    if (selector is ast.ElementSelector) {
      return selector.isWildcard || selector.name.toLowerCase() == element.tag;
    }
    if (selector is ast.IdSelector) {
      return element.attributes['id'] == selector.name;
    }
    if (selector is ast.ClassSelector) {
      return (element.attributes['class'] ?? '')
          .split(RegExp(r'[ \t\r\n\f]+'))
          .contains(selector.name);
    }
    return false;
  }

  bool _matches(ast.Selector selector, CssElement element) {
    final sequences = selector.simpleSelectorSequences;
    bool match(int index, CssElement? current) {
      if (current == null ||
          !_simple(sequences[index].simpleSelector, current)) {
        return false;
      }
      if (index == 0) return true;
      final seq = sequences[index];
      if (seq.isCombinatorNone) return match(index - 1, current);
      if (seq.isCombinatorGreater) return match(index - 1, current.parent);
      var ancestor = current.parent;
      while (ancestor != null) {
        if (match(index - 1, ancestor)) return true;
        ancestor = ancestor.parent;
      }
      return false;
    }

    return sequences.isNotEmpty && match(sequences.length - 1, element);
  }

  ComputedVisibility compute(CssElement element, ComputedVisibility parent) {
    String? display, visibility;
    final ranks = <String, (bool, int, int)>{};
    void apply(
      String property,
      String value,
      bool important,
      int specificity,
      int order,
    ) {
      final old = ranks[property];
      final wins =
          old == null ||
          (important && !old.$1) ||
          important == old.$1 &&
              (specificity > old.$2 ||
                  specificity == old.$2 && order >= old.$3);
      if (!wins) return;
      ranks[property] = (important, specificity, order);
      if (property == 'display') {
        display = value;
      } else {
        visibility = value;
      }
    }

    for (final rule in _rules) {
      if (_matches(rule.selector, element)) {
        apply(
          rule.property,
          rule.value,
          rule.important,
          rule.specificity,
          rule.order,
        );
      }
    }
    final inline = element.attributes['style'];
    if (inline != null) {
      final size = utf8.encode(inline).length;
      _bytes += size;
      if (size > EpubLimits.attributeBytes ||
          _bytes > EpubLimits.cssTotalBytes) {
        throw const BookFailure(BookError.limitExceeded);
      }
      _guardComplexity(inline);
      final errors = <css.Message>[];
      final sheet = css.parse('x {$inline}', errors: errors);
      if (errors.isNotEmpty ||
          sheet.topLevels.length != 1 ||
          sheet.topLevels.single is! ast.RuleSet) {
        throw const BookFailure(BookError.invalidContent);
      }
      for (final rule in sheet.topLevels.whereType<ast.RuleSet>()) {
        for (final d
            in rule.declarationGroup.declarations
                .whereType<ast.Declaration>()) {
          final prop = d.property.toLowerCase();
          final value = d.expression?.span?.text.trim().toLowerCase() ?? '';
          if (prop == 'display' &&
                  [
                    'none',
                    'block',
                    'inline',
                    'inline-block',
                    'list-item',
                    'table',
                    'table-row',
                    'table-cell',
                  ].contains(value) ||
              prop == 'visibility' &&
                  ['hidden', 'visible', 'collapse'].contains(value)) {
            apply(prop, value, d.important, 1000000, _order++);
          } else {
            warnings.add('unsupportedCss');
          }
        }
      }
    }
    return ComputedVisibility(
      displayOff:
          parent.displayOff ||
          element.attributes.containsKey('hidden') ||
          display == 'none',
      visible: visibility == null ? parent.visible : visibility == 'visible',
    );
  }
}
