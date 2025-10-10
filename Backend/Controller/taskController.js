import mongoose from "mongoose";
import Task from "../Models/Task.js";
import Project from "../Models/Project.js";
import Client from "../Models/Client.js";
import SubCompany from "../Models/SubCompany.js";
import User from "../Models/userSchema.js";
 
export const addTask = async (req, res) => {
  try {
    const {
      title,
      description,
      project,
      client,
      subCompany,
      assignedTo,
      priority,
      status,
      deadline,
      attachments,
      comments,
    } = req.body;

    if (!title) {
      return res.status(400).json({ success: false, message: "Title is required" });
    }

    // ✅ Validate IDs
    const validateId = (id, name) => {
      if (id && !mongoose.Types.ObjectId.isValid(id)) {
        throw new Error(`Invalid ${name} ID`);
      }
    };
    validateId(project, "project");
    validateId(client, "client");
    validateId(subCompany, "subCompany");

    // ✅ Validate assignedTo as an array
    if (assignedTo && !Array.isArray(assignedTo)) {
      return res.status(400).json({ success: false, message: "assignedTo must be an array of user IDs" });
    }

    // ✅ Validate all user IDs
    if (assignedTo && assignedTo.length > 0) {
      for (const userId of assignedTo) {
        if (!mongoose.Types.ObjectId.isValid(userId)) {
          return res.status(400).json({ success: false, message: `Invalid user ID: ${userId}` });
        }
        const exists = await User.findById(userId);
        if (!exists) {
          return res.status(404).json({ success: false, message: `User not found: ${userId}` });
        }
      }
    }

    const task = await Task.create({
      title,
      description,
      project,
      client,
      subCompany,
      createdBy: req.user?._id || null,
      assignedTo,
      priority: priority || "medium",
      status: status || "open",
      deadline,
      attachments,
      comments,
      logs: [
        {
          action: "Task created",
          by: req.user?._id || null,
          at: new Date(),
        },
      ],
    });

    return res.status(201).json({
      success: true,
      message: "Task created successfully",
      data: task,
    });
  } catch (err) {
    console.error("Error creating task:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};

export const updateTask = async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;

    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid task ID" });

    const task = await Task.findById(id);
    if (!task)
      return res.status(404).json({ success: false, message: "Task not found" });

    if (updates.assignedTo && Array.isArray(updates.assignedTo)) {
      for (const userId of updates.assignedTo) {
        if (!mongoose.Types.ObjectId.isValid(userId)) {
          return res.status(400).json({ success: false, message: `Invalid user ID: ${userId}` });
        }
        const exists = await User.findById(userId);
        if (!exists) {
          return res.status(404).json({ success: false, message: `User not found: ${userId}` });
        }
      }
      task.assignedTo = updates.assignedTo;
    }
    const allowedFields = [
      "title",
      "description",
      "priority",
      "status",
      "deadline",
      "attachments",
      "comments",
    ];

    for (const key of Object.keys(updates)) {
      if (allowedFields.includes(key)) {
        task[key] = updates[key];
      }
    }

    // Log the change
    task.logs.push({
      action: "Task updated",
      by: req.user?._id || null,
      at: new Date(),
      extra: updates,
    });

    await task.save();

    res.status(200).json({
      success: true,
      message: "Task updated successfully",
      data: task,
    });
  } catch (err) {
    console.error("Error updating task:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};


export const deleteTask = async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid task ID" });

    const task = await Task.findById(id);
    if (!task)
      return res.status(404).json({ success: false, message: "Task not found" });

    await task.deleteOne();
    res.status(200).json({ success: true, message: "Task deleted successfully" });
  } catch (err) {
    console.error("Error deleting task:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};

export const getAllTasks = async (req, res) => {
  try {
    const { status, priority, assignedTo, project, client, subCompany, search } = req.query;
    const filter = {};

    if (status) filter.status = status;
    if (priority) filter.priority = priority;
    if (project) filter.project = project;
    if (client) filter.client = client;
    if (subCompany) filter.subCompany = subCompany;
    if (assignedTo) filter.assignedTo = assignedTo;
    if (search) filter.title = { $regex: search, $options: "i" };

    const tasks = await Task.find(filter)
      .populate("project", "title")
      .populate("client", "name")
      .populate("subCompany", "name")
      .populate("assignedTo", "fullName email")
      .populate("createdBy", "fullName email")
      .sort({ createdAt: -1 });

    res.status(200).json({
      success: true,
      count: tasks.length,
      data: tasks,
    });
  } catch (err) {
    console.error("Error fetching tasks:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};

export const getTaskById = async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id))
      return res.status(400).json({ success: false, message: "Invalid task ID" });

    const task = await Task.findById(id)
      .populate("project", "title")
      .populate("client", "name")
      .populate("subCompany", "name")
      .populate("assignedTo", "fullName email")
      .populate("createdBy", "fullName email")
      .populate("comments.by", "fullName");

    if (!task)
      return res.status(404).json({ success: false, message: "Task not found" });

    res.status(200).json({ success: true, data: task });
  } catch (err) {
    console.error("Error fetching task:", err);
    res.status(500).json({ success: false, message: err.message });
  }
};
