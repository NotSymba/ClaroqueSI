package warehouse;

import javax.swing.*;
import java.awt.*;

public class WarehouseView extends JFrame {

    private static final int CELL_SIZE = 40;
    private static final int INFO_PANEL_WIDTH = 450;
    private static final int CONSOLE_HEIGHT = 180;

    private WarehouseModel warehouse;
    private int gridWidth;
    private int gridHeight;

    private WarehousePanel warehousePanel;
    private JPanel infoPanel;
    private JPanel consolePanel;   // declarado aquí, una sola vez
    private JTextArea statsArea;
    private JTextArea robotsArea;
    private JTextArea shelvesArea;
    private JTextArea consoleArea;

    public WarehouseView(WarehouseModel warehouse, int gridWidth, int gridHeight) {
        this.warehouse = warehouse;
        this.gridWidth = gridWidth;
        this.gridHeight = gridHeight;

        initComponents();
        setupLayout();

        setTitle("Warehouse Management System - Jason/JaCaMo");
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        pack();
        setLocationRelativeTo(null);

        Timer timer = new Timer(1000, e -> update());
        timer.start();
    }

    private void initComponents() {
        warehousePanel = new WarehousePanel();

        // ---- Panel de información (derecha) ----
        infoPanel = new JPanel();
        infoPanel.setLayout(new BoxLayout(infoPanel, BoxLayout.Y_AXIS));
        infoPanel.setPreferredSize(new Dimension(INFO_PANEL_WIDTH, gridHeight * CELL_SIZE));
        infoPanel.setBackground(new Color(240, 240, 240));
        infoPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        JLabel statsLabel = new JLabel("📊 Statistics");
        statsLabel.setFont(new Font("Arial", Font.BOLD, 15));
        statsLabel.setAlignmentX(Component.LEFT_ALIGNMENT);

        statsArea = new JTextArea(6, 35);
        statsArea.setEditable(false);
        statsArea.setFont(new Font("Monospaced", Font.PLAIN, 12));
        statsArea.setBackground(Color.WHITE);
        statsArea.setForeground(Color.BLACK);
        statsArea.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 5));
        JScrollPane statsScroll = new JScrollPane(statsArea);
        statsScroll.setAlignmentX(Component.LEFT_ALIGNMENT);
        statsScroll.setPreferredSize(new Dimension(430, 110));

        JLabel robotsLabel = new JLabel("🤖 Robots");
        robotsLabel.setFont(new Font("Arial", Font.BOLD, 15));
        robotsLabel.setAlignmentX(Component.LEFT_ALIGNMENT);

        robotsArea = new JTextArea(10, 35);
        robotsArea.setEditable(false);
        robotsArea.setFont(new Font("Monospaced", Font.PLAIN, 11));
        robotsArea.setBackground(Color.WHITE);
        robotsArea.setForeground(Color.BLACK);
        robotsArea.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 5));
        JScrollPane robotsScroll = new JScrollPane(robotsArea);
        robotsScroll.setAlignmentX(Component.LEFT_ALIGNMENT);
        robotsScroll.setPreferredSize(new Dimension(430, 180));

        JLabel shelvesLabel = new JLabel("📦 Shelves");
        shelvesLabel.setFont(new Font("Arial", Font.BOLD, 15));
        shelvesLabel.setAlignmentX(Component.LEFT_ALIGNMENT);

        shelvesArea = new JTextArea(12, 35);
        shelvesArea.setEditable(false);
        shelvesArea.setFont(new Font("Monospaced", Font.PLAIN, 11));
        shelvesArea.setBackground(Color.WHITE);
        shelvesArea.setForeground(Color.BLACK);
        shelvesArea.setBorder(BorderFactory.createEmptyBorder(5, 5, 5, 5));
        JScrollPane shelvesScroll = new JScrollPane(shelvesArea);
        shelvesScroll.setAlignmentX(Component.LEFT_ALIGNMENT);
        shelvesScroll.setPreferredSize(new Dimension(430, 220));

        infoPanel.add(statsLabel);
        infoPanel.add(Box.createVerticalStrut(5));
        infoPanel.add(statsScroll);
        infoPanel.add(Box.createVerticalStrut(15));
        infoPanel.add(robotsLabel);
        infoPanel.add(Box.createVerticalStrut(5));
        infoPanel.add(robotsScroll);
        infoPanel.add(Box.createVerticalStrut(15));
        infoPanel.add(shelvesLabel);
        infoPanel.add(Box.createVerticalStrut(5));
        infoPanel.add(shelvesScroll);

        // ---- Panel de consola (abajo) ----
        consolePanel = new JPanel(new BorderLayout());
        consolePanel.setPreferredSize(
                new Dimension(gridWidth * CELL_SIZE + INFO_PANEL_WIDTH, CONSOLE_HEIGHT));

        JLabel consoleLabel = new JLabel("📝 Console - Robot Activity Log");
        consoleLabel.setFont(new Font("Arial", Font.BOLD, 14));
        consoleLabel.setBorder(BorderFactory.createEmptyBorder(5, 10, 5, 10));
        consoleLabel.setOpaque(true);
        consoleLabel.setBackground(new Color(60, 60, 60));
        consoleLabel.setForeground(Color.WHITE);

        consoleArea = new JTextArea();
        consoleArea.setEditable(false);
        consoleArea.setFont(new Font("Monospaced", Font.PLAIN, 11));
        consoleArea.setBackground(new Color(30, 30, 30));
        consoleArea.setForeground(new Color(200, 255, 200));
        consoleArea.setLineWrap(true);
        consoleArea.setWrapStyleWord(true);

        JScrollPane consoleScroll = new JScrollPane(consoleArea);
        consoleScroll.setVerticalScrollBarPolicy(JScrollPane.VERTICAL_SCROLLBAR_ALWAYS);

        consolePanel.add(consoleLabel, BorderLayout.NORTH);
        consolePanel.add(consoleScroll, BorderLayout.CENTER);
    }

    private void setupLayout() {
        setLayout(new BorderLayout());
        add(warehousePanel, BorderLayout.CENTER);
        add(infoPanel, BorderLayout.EAST);
        add(consolePanel, BorderLayout.SOUTH);
    }

    // -------------------------------------------------------------------------
    // API PÚBLICA
    // -------------------------------------------------------------------------

    public void update() {
        warehousePanel.repaint();
        updateInfo();
    }

    /**
     * Añade un mensaje a la consola con timestamp.
     * Limita el contenido a 500 líneas para evitar crecimiento ilimitado de memoria.
     */
    public void logMessage(String message) {
        SwingUtilities.invokeLater(() -> {
            String timestamp = String.format("[%tT] ", System.currentTimeMillis());
            consoleArea.append(timestamp + message + "\n");
            consoleArea.setCaretPosition(consoleArea.getDocument().getLength());

            // Recortar: obtener líneas, eliminar las más antiguas si pasan de 500
            String text = consoleArea.getText();
            int count = 0;
            int pos = text.length();
            // Contar líneas desde el final
            while (pos > 0 && count < 500) {
                int nl = text.lastIndexOf('\n', pos - 1);
                if (nl < 0) break;
                count++;
                pos = nl;
            }
            // Si hay más de 500 líneas, eliminar el texto anterior a 'pos'
            if (count == 500 && pos > 0) {
                consoleArea.replaceRange("", 0, pos + 1);
            }
        });
    }

    // -------------------------------------------------------------------------
    // ACTUALIZACIÓN DEL PANEL DE INFO
    // -------------------------------------------------------------------------

    private void updateInfo() {
        statsArea.setText(warehouse.getStatistics());

        StringBuilder robotsText = new StringBuilder();
        for (Robot robot : warehouse.getRobots().values()) {
            robotsText.append(String.format("%-12s [%s]\n", robot.getId(), robot.getType()));
            robotsText.append(String.format("  Pos: (%d,%d)\n", robot.getX(), robot.getY()));
            robotsText.append(String.format("  Busy: %s\n", robot.isBusy() ? "YES" : "NO"));
            if (robot.isCarrying()) {
                robotsText.append(String.format("  Carrying: %s\n",
                        robot.getCarriedContainer().getId()));
            }
            robotsText.append("\n");
        }
        robotsArea.setText(robotsText.toString());

        StringBuilder shelvesText = new StringBuilder();
        for (Shelf shelf : warehouse.getShelves().values()) {
            shelvesText.append(String.format("%-10s @(%d,%d)\n",
                    shelf.getId(), shelf.getX(), shelf.getY()));
            shelvesText.append(String.format("  Occupancy: %.1f%%\n",
                    shelf.getOccupancyPercentage()));
            shelvesText.append(String.format("  Weight: %.1f/%.1fkg\n",
                    shelf.getCurrentWeight(), shelf.getMaxWeight()));
            shelvesText.append(String.format("  Volume: %d/%d\n",
                    shelf.getCurrentVolume(), shelf.getMaxVolume()));
            shelvesText.append(String.format("  Items: %d\n",
                    shelf.getStoredContainers().size()));
            shelvesText.append("\n");
        }
        shelvesArea.setText(shelvesText.toString());
    }

    // -------------------------------------------------------------------------
    // PANEL DE DIBUJO
    // -------------------------------------------------------------------------

    class WarehousePanel extends JPanel {

        public WarehousePanel() {
            setPreferredSize(new Dimension(gridWidth * CELL_SIZE, gridHeight * CELL_SIZE));
            setBackground(Color.WHITE);
        }

        @Override
        protected void paintComponent(Graphics g) {
            super.paintComponent(g);
            Graphics2D g2d = (Graphics2D) g;
            g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);

            drawGrid(g2d);
            drawShelves(g2d);
            drawContainers(g2d);
            drawRobots(g2d);
        }

        private void drawGrid(Graphics2D g) {
            CellType[][] grid = warehouse.getGrid();

            for (int x = 0; x < gridWidth; x++) {
                for (int y = 0; y < gridHeight; y++) {
                    int px = x * CELL_SIZE;
                    int py = y * CELL_SIZE;

                    switch (grid[x][y]) {
                        case EMPTY:
                            g.setColor(new Color(250, 250, 250));
                            break;
                        case ENTRANCE:
                            g.setColor(new Color(200, 255, 200));
                            break;
                        case CLASSIFICATION:
                            g.setColor(new Color(255, 255, 200));
                            break;
                        case SHELF:
                            g.setColor(new Color(180, 180, 200));
                            break;
                        case BLOCKED:
                            g.setColor(new Color(255, 100, 100));
                            break;
                        case PACKAGE:
                            g.setColor(new Color(210, 30, 30));
                            break;
                        case EXIT:
                            g.setColor(new Color(30, 30, 220));
                            break;
                        default:
                            g.setColor(Color.WHITE);
                    }

                    g.fillRect(px, py, CELL_SIZE, CELL_SIZE);
                    g.setColor(new Color(200, 200, 200));
                    g.drawRect(px, py, CELL_SIZE, CELL_SIZE);
                }
            }
        }

        private void drawShelves(Graphics2D g) {
            for (Shelf shelf : warehouse.getShelves().values()) {
                int px = shelf.getX() * CELL_SIZE;
                int py = shelf.getY() * CELL_SIZE;
                int width = shelf.getWidth() * CELL_SIZE;
                int height = shelf.getHeight() * CELL_SIZE;

                double occupancy = shelf.getOccupancyPercentage();
                Color shelfColor;
                if (occupancy < 50) {
                    shelfColor = new Color(100, 200, 100);
                } else if (occupancy < 80) {
                    shelfColor = new Color(255, 200, 100);
                } else {
                    shelfColor = new Color(255, 100, 100);
                }

                g.setColor(shelfColor);
                g.fillRect(px + 2, py + 2, width - 4, height - 4);
                g.setColor(Color.BLACK);
                g.drawRect(px + 2, py + 2, width - 4, height - 4);

                g.setFont(new Font("Arial", Font.PLAIN, 8));
                g.drawString(shelf.getId().replace("shelf_", "S"), px + 5, py + 12);
                g.drawString(String.format("%.0f%%", occupancy), px + 5, py + height - 5);
            }
        }

        private void drawContainers(Graphics2D g) {
            // Construir set de IDs de contenedores que están siendo cargados,
            // para no iterar sobre todos los robots por cada contenedor
            java.util.Set<String> carriedIds = new java.util.HashSet<>();
            for (Robot robot : warehouse.getRobots().values()) {
                if (robot.isCarrying()) {
                    carriedIds.add(robot.getCarriedContainer().getId());
                }
            }

            for (Container container : warehouse.getContainers().values()) {
                // No dibujar contenedores en tránsito ni ya depositados en estantería
                if (carriedIds.contains(container.getId())) continue;
                if (container.getAssignedShelf() != null) continue;

                int px = container.getX() * CELL_SIZE;
                int py = container.getY() * CELL_SIZE;

                Color containerColor;
                switch (container.getType()) {
                    case "fragile":
                        containerColor = new Color(255, 200, 200);
                        break;
                    case "urgent":
                        containerColor = new Color(255, 150, 0);
                        break;
                    default:
                        containerColor = new Color(150, 150, 255);
                }

                g.setColor(containerColor);
                g.fillRect(px + 10, py + 10, CELL_SIZE - 20, CELL_SIZE - 20);
                g.setColor(Color.BLACK);
                g.drawRect(px + 10, py + 10, CELL_SIZE - 20, CELL_SIZE - 20);

                g.setFont(new Font("Arial", Font.PLAIN, 8));
                g.drawString(container.getId().replace("container_", "C"), px + 12, py + 22);
            }
        }

        private void drawRobots(Graphics2D g) {
            for (Robot robot : warehouse.getRobots().values()) {
                int px = robot.getX() * CELL_SIZE;
                int py = robot.getY() * CELL_SIZE;

                Color robotColor;
                switch (robot.getType()) {
                    case "light":
                        robotColor = new Color(100, 255, 100);
                        break;
                    case "medium":
                        robotColor = new Color(100, 200, 255);
                        break;
                    case "heavy":
                        robotColor = new Color(255, 100, 255);
                        break;
                    default:
                        robotColor = Color.GRAY;
                }

                g.setColor(robotColor);
                g.fillOval(px + 5, py + 5, CELL_SIZE - 10, CELL_SIZE - 10);
                g.setColor(Color.BLACK);
                g.setStroke(new BasicStroke(2));
                g.drawOval(px + 5, py + 5, CELL_SIZE - 10, CELL_SIZE - 10);
                g.setStroke(new BasicStroke(1));

                g.setFont(new Font("Arial", Font.BOLD, 9));
                String shortId = robot.getId().replace("robot_", "");
                FontMetrics fm = g.getFontMetrics();
                int textWidth = fm.stringWidth(shortId);
                g.drawString(shortId, px + (CELL_SIZE - textWidth) / 2, py + CELL_SIZE / 2 + 3);

                // Indicador de carga encima del robot
                if (robot.isCarrying()) {
                    g.setColor(new Color(255, 200, 0));
                    g.fillRect(px + CELL_SIZE - 15, py + 3, 12, 12);
                    g.setColor(Color.BLACK);
                    g.drawRect(px + CELL_SIZE - 15, py + 3, 12, 12);
                }
            }
        }
    }
}