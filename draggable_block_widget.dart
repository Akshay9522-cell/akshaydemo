import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DraggableBlockWidget extends StatefulWidget {
  final BlockShape block;
  final List<List<dynamic>> grid;
  final GlobalKey gridKey;
  final double cellSize;
  final Function(BlockShape, int, int) onPlaceBlock;
  final Function(List<List<dynamic>>) onPreviewUpdate;

  const DraggableBlockWidget({
    Key? key,
    required this.block,
    required this.grid,
    required this.gridKey,
    required this.cellSize,
    required this.onPlaceBlock,
    required this.onPreviewUpdate,
  }) : super(key: key);

  @override
  State<DraggableBlockWidget> createState() => _DraggableBlockWidgetState();
}

class _DraggableBlockWidgetState extends State<DraggableBlockWidget> {
  bool isDragging = false;
  List<List<dynamic>> previewGrid = [];
  Offset? _lastDropPos;
  
  // Constants for consistent calculations
  static const double blockPadding = 8.0;
  static const double dragFeedbackOffset = 50.0;

  @override
  void initState() {
    super.initState();
    previewGrid = List.generate(10, (_) => List.filled(10, null));
  }

  /// Calculate the cell size within the block widget accounting for padding
  double _getBlockCellSize(Size blockWidgetSize) {
    return (blockWidgetSize.width - (blockPadding * 2)) / widget.block.shape[0].length;
  }

  /// Convert local position to block cell coordinates
  Point<int> _localPositionToBlockCell(Offset localPosition, double blockCellSize) {
    int col = (localPosition.dx / blockCellSize).floor();
    int row = (localPosition.dy / blockCellSize).floor();
    
    // Clamp to valid block bounds
    col = col.clamp(0, widget.block.shape[0].length - 1);
    row = row.clamp(0, widget.block.shape.length - 1);
    
    return Point(col, row);
  }

  /// Convert block cell coordinates to offset position
  Offset _blockCellToOffset(Point<int> cell, double blockCellSize) {
    double offsetX = (cell.x * blockCellSize) + (blockCellSize / 2) + blockPadding;
    double offsetY = (cell.y * blockCellSize) + (blockCellSize / 2) + blockPadding;
    return Offset(offsetX, offsetY);
  }

  /// Find the first non-empty cell in the block as fallback
  Point<int> _findFirstNonEmptyCell() {
    for (int row = 0; row < widget.block.shape.length; row++) {
      for (int col = 0; col < widget.block.shape[row].length; col++) {
        if (widget.block.shape[row][col] != 0) {
          return Point(col, row);
        }
      }
    }
    return const Point(0, 0);
  }

  /// Convert grid coordinates to block-relative coordinates
  Point<int> _gridToBlockCoordinates(Point<int> gridCell, Point<int> dragStartCell) {
    return Point(
      gridCell.x - dragStartCell.x,
      gridCell.y - dragStartCell.y,
    );
  }

  Widget _buildDraggableBlock(BlockShape block) {
    return Listener(
      onPointerDown: (details) {
        final RenderBox blockBox = context.findRenderObject() as RenderBox;
        final Size blockWidgetSize = blockBox.size;
        final double blockCellSize = _getBlockCellSize(blockWidgetSize);

        // Account for padding in local position
        final Offset adjustedLocalPos = Offset(
          details.localPosition.dx - blockPadding,
          details.localPosition.dy - blockPadding,
        );

        final Point<int> touchedCell = _localPositionToBlockCell(adjustedLocalPos, blockCellSize);

        // Verify the touched cell is part of the block
        if (touchedCell.y >= 0 && touchedCell.y < block.shape.length &&
            touchedCell.x >= 0 && touchedCell.x < block.shape[touchedCell.y].length &&
            block.shape[touchedCell.y][touchedCell.x] != 0) {
          block.dragStartRow = touchedCell.y;
          block.dragStartCol = touchedCell.x;
        } else {
          // Fallback to first non-empty cell
          final Point<int> firstCell = _findFirstNonEmptyCell();
          block.dragStartRow = firstCell.y;
          block.dragStartCol = firstCell.x;
        }
      },
      child: Draggable<BlockShape>(
        data: block,
        dragAnchorStrategy: (draggable, context, position) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final Size size = box.size;
          final double blockCellSize = _getBlockCellSize(size);

          // Account for padding in position
          final Offset adjustedPosition = Offset(
            position.dx - blockPadding,
            position.dy - blockPadding,
          );

          final Point<int> touchedCell = _localPositionToBlockCell(adjustedPosition, blockCellSize);
          final Offset cellCenterOffset = _blockCellToOffset(touchedCell, blockCellSize);

          // Apply the drag feedback offset (shadow above finger)
          return Offset(cellCenterOffset.dx, cellCenterOffset.dy - dragFeedbackOffset);
        },
        feedback: Transform.scale(
          scale: 1.2,
          child: Material(
            elevation: 8,
            color: Colors.transparent,
            shadowColor: Colors.black.withOpacity(0.3),
            child: Opacity(
              opacity: 0.9,
              child: GameWidgets.buildBlockWidget(block, isDragging: true, noPadding: true),
            ),
          ),
        ),
        childWhenDragging: AnimatedOpacity(
          opacity: 0.3,
          duration: const Duration(milliseconds: 200),
          child: GameWidgets.buildBlockWidget(block),
        ),
        child: GameWidgets.buildBlockWidget(block),
        onDragStarted: () {
          HapticFeedback.selectionClick();
          setState(() => isDragging = true);
        },
        onDragUpdate: (details) {
          final RenderBox? gridBox = widget.gridKey.currentContext?.findRenderObject() as RenderBox?;
          if (gridBox == null || widget.cellSize == 0) return;

          // Convert global position to grid local position
          final Offset gridLocalPosition = gridBox.globalToLocal(details.globalPosition);
          
          // Apply the same offset used in dragAnchorStrategy for consistency
          final Offset adjustedPosition = Offset(
            gridLocalPosition.dx,
            gridLocalPosition.dy - dragFeedbackOffset,
          );

          // Convert to grid cell coordinates
          final int gridCol = (adjustedPosition.dx / widget.cellSize).floor();
          final int gridRow = (adjustedPosition.dy / widget.cellSize).floor();

          // Calculate the block's top-left position on the grid
          final Point<int> dragStartCell = Point(
            block.dragStartCol ?? 0,
            block.dragStartRow ?? 0,
          );
          
          final Point<int> blockTopLeft = Point(
            gridCol - dragStartCell.x,
            gridRow - dragStartCell.y,
          );

          // Only update if position changed
          final Offset newDropPos = Offset(blockTopLeft.x.toDouble(), blockTopLeft.y.toDouble());
          if (_lastDropPos != newDropPos) {
            _lastDropPos = newDropPos;
            previewGrid = GameLogic.updatePreview(
              block,
              blockTopLeft.y,
              blockTopLeft.x,
              widget.grid,
            );
            widget.onPreviewUpdate(previewGrid);
            setState(() {});
          }
        },
        onDragEnd: (details) async {
          if (_lastDropPos != null) {
            final int blockRow = _lastDropPos!.dy.toInt();
            final int blockCol = _lastDropPos!.dx.toInt();

            widget.onPlaceBlock(block, blockRow, blockCol);
          }

          // Small delay for smooth animation
          await Future.delayed(const Duration(milliseconds: 100));

          setState(() {
            isDragging = false;
            previewGrid = List.generate(10, (_) => List.filled(10, null));
            _lastDropPos = null;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildDraggableBlock(widget.block);
  }
}

// Helper class for coordinate handling
class Point<T extends num> {
  final T x;
  final T y;

  const Point(this.x, this.y);

  @override
  String toString() => 'Point($x, $y)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point && runtimeType == other.runtimeType && x == other.x && y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

// Placeholder classes - replace with your actual implementations
class BlockShape {
  List<List<int>> shape;
  int? dragStartRow;
  int? dragStartCol;

  BlockShape({required this.shape});
}

class GameWidgets {
  static Widget buildBlockWidget(BlockShape block, {bool isDragging = false, bool noPadding = false}) {
    // Your existing block widget implementation
    return Container(); // Placeholder
  }
}

class GameLogic {
  static List<List<dynamic>> updatePreview(BlockShape block, int row, int col, List<List<dynamic>> grid) {
    // Your existing preview logic
    return grid; // Placeholder
  }
}