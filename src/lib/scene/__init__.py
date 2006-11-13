__author__ = 'Robert Ancell <bob27@users.sourceforge.net>'
__license__ = 'GNU General Public License Version 2'
__copyright__ = 'Copyright 2005-2006  Robert Ancell'

# Highlight types
HIGHLIGHT_SELECTED = 'selected'
HIGHLIGHT_CAN_MOVE = 'canMove'

class ChessSet:
    """
    """

    def drawPiece(self, pieceName, state, context = None):
        """Draw a piece.
        
        'pieceName' is the piece name (string).
        'state' is the piece state (string).
        'context' is a reference to the rendering context being used (user-defined).
        """
        pass
    
class ChessPiece:
    """Abstract class for a glChess chess piece model"""
    
    def move(self, coord):
        """Move this piece to a board location.
        
        'coord' is a 2-tuple containing the file and rank of the board location to move to.
                The values are:

                       Black
                (0,7) +-----+ (7,7)
                      |     |
                      |     |
                (0,0) +-----+ (7,0)
                       White
        """
        pass
    
class Scene:
    """Abstract class for glChess scenes
    
    Extend this class to make a scene
    """
    
    # Metheds to extend by a higher class
    
    def onRedraw(self):
        """This method is called when the scene needs redrawing"""
        pass
    
    def startAnimation(self):
        """Called when the animate() method should be called"""
        pass

    # Methods to implement
    
    def reshape(self, width, height):
        """Resize the viewport into the scene.
        
        'width' is the width of the viewport in pixels.
        'height' is the width of the viewport in pixels.
        """
        pass

    def addChessPiece(self, chessSet, name, coord):
        """Add a chess piece model into the scene.
        
        'chessSet' is the name of the chess set (string).
        'name' is the name of the piece (string).
        'coord' is the the chess board location of the piece (tuple, (file,rank)).
        
        Returns a reference to this chess piece or raises an exception.
        """
        raise Exception('Not implemented')

    def removeChessPiece(self, piece):
        """Remove chess piece.
        
        'piece' is a chess piece instance as returned by addChessPiece().
        """
        pass
        
    def setBoardHighlight(self, coords):
        """Highlight a square on the board.
        
        'coords' is a dictionary of highlight types keyed by square co-ordinates.
                 The co-ordinates are a tuple in the form (file,rank).
                 If None the highlight will be cleared.
        """
        pass
    
    def setBoardRotation(self, angle):
        """Set the rotation on the board.
        
        'angle' is the angle the board should be drawn at in degress (float, [0.0, 360.0]).
        """
        pass
    
    def animate(self, timeStep):
        """Animate the scene.
        
        'timeStep' is the time since this method has last been called in seconds (float).
        
        Returns False once all animation is complete otherwise returns True. Once animation
        is complete do not call this method again until startAnimation() is called.
        """
        pass

    def render(self, context):
        """Manually render the scene.
        
        'context' TODO
        """
        pass

    def getSquare(self, x, y):
        """Find the chess square at a given 2D location.
        
        'x' is the number of pixels from the left of the scene to select.
        'y' is the number of pixels from the bottom of the scene to select.
        
        This requires an OpenGL context.
        
        Return the co-ordinate in LAN format (string) or None if no square at this point.
        """
        return None